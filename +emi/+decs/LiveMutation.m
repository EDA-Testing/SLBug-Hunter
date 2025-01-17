classdef LiveMutation < emi.decs.DecoratedMutator
    %DEADBLOCKDELETESTRATEGY Summary of this class goes here
    %   Detailed explanation goes here


    properties
        % skip mutation op if filter returns true.
        % key: mut_op_id, val: lambda
        mutop_skip = containers.Map(...
            );

        % mutation-op specific arguments which would be passed to mutation
        % implementers
        mutop_args;

        % Blocks which output be used to generate conditions for if blocks
        if_cond_gen_blocks;

        % Whether the block can be put inside an action subsystem to
        % implement always true/false mutations.
        valid_for_if_target;

        % Keep track of blocks mutated via always-if.
        % We cannot mutate a block twice as its type change to action ss

        if_target_not_mutated; % still not mutated i.e. available for mutation

    end

    methods

        function obj = LiveMutation(varargin)
            obj = obj@emi.decs.DecoratedMutator(varargin{:});
            obj.mutop_args = {};
        end


        function main_phase(obj)
            %%
            e = [];

            obj.init();

            try
                if size(obj.r.live_blocks, 1) == 0
                    obj.l.warn('No live blocks in the original model! Returning from Decorator.');
                    return;
                end

                live_blocks = obj.r.sample_live_blocks();
                live_blocks = cellfun(@(p) [obj.mutant.sys '/' p],...
                    live_blocks, 'UniformOutput', false);

                % blocks may have repeated contents. Use the following if you
                % want to not mutate with replacement.
                [live_blocks, blk_idx] = unique(live_blocks);
                for i=1:size(live_blocks,1)
                    live_blocks(i);
                    A=cell2mat(live_blocks(i));
                    a=strsplit(A,'/');
                    if size(a,2)>2
                        live_blocks(i)={1};
                    end
                end

                live_blocks=live_blocks(cellfun(@(p)~isequal(p,1),live_blocks));
                [live_blocks, blk_idx] = unique(live_blocks);
                % blk_idx = ones(length(live_blocks), 1); % repeatation allowed
                %% 筛选出单通模块并明确不在source库里面
                p=1;
                live_block = {};
                for i = 1:size(live_blocks,1)
                    filter_input = get_param(live_blocks{i},'PortHandles').Inport;
%                     filter_output = get_param(live_block{i},'PortHandles').Outport;
                    if size(filter_input,2) == 1
                            live_block{p,1} = live_blocks{i};
                            p = p+1;
                    end
                end
                [live_block, blk_idx] = unique(live_block);
                cellfun( ...
                    @(p, op) obj.mutate_a_block(p, [], op) ...
                    , live_block, obj.r.live_ops(blk_idx))

            catch e
                rethrow(e);
            end

            if ~isempty(e)
                rethrow(e);
            end

        end

        function ret = mutate_a_block(obj, block, contex_sys, mut_op_id)
            %% MUTATE A BLOCK `block` using `mut_op`

            ret = true;

            if iscell(block)
                % Recursive call when `block` is a cell
                for b_i = 1:numel(block)
                    obj.mutate_a_block([contex_sys '/' block{b_i}], contex_sys);
                end
                return;
            end

            mut_op = emi.cfg.LIVE_MUT_OPS{mut_op_id};

            block = obj.change_block(block, mut_op_id);

            if isempty(block)
                skip = true;
                obj.l.info('阻断成功')
            else
                skip = false;
            end

            blacklist = emi.cfg.MUT_OP_BLACKLIST{mut_op_id};

            skip = skip ||  blacklist.isKey(cps.slsf.btype(block)) ;

            % Check if predecessor has constant sample time

            if ~ skip

                try
                    [connections,sources,destinations] = emi.slsf.get_connections(block, true, true);
                catch e
                    rethrow(e);
                end

                try
                    if mut_op_id == 2 && ~isempty(sources)
                        skip = skip || emi.live.modelreffilter(obj.mutant, sources);
                    end
                catch e
                    rethrow(e);
                end


                if obj.mutop_skip.isKey(mut_op_id)
                    wo_parent = utility.strip_first_split(block, '/');
                    fn = obj.mutop_skip(mut_op_id);
                    skip =  fn(obj, wo_parent);
                end

            end


            if skip
                obj.l.debug('Not mutating %s',...
                    block);
                obj.r.n_live_skipped = obj.r.n_live_skipped + 1;
                return;
            end

            is_block_not_action_subsystem = all(...
                ~strcmpi(connections{:, 'Type'}, 'ifaction'));

            is_if_block = strcmp(get_param(block, 'blockType'), 'If');

            if is_if_block || ~is_block_not_action_subsystem
                obj.r.n_live_skipped = obj.r.n_live_skipped + 1;
                return;
            end

            [block_parent, this_block] = utility.strip_last_split(block, '/');

            %             hilite_system(block);

            % Pause for containing (parent) subsystem or the block iteself?
            pause_d = emi.pause_for_ss(block_parent, block);

            if pause_d
                % Enable breakpoints
                disp('Pause for debugging');
            end

            % To enable hilighting and pausing, uncomment the following:
            %             emi.hilite_system(block, emi.cfg.DELETE_BLOCK_P || pause_ss);
            %             emi.pause_interactive(emi.cfg.DELETE_BLOCK_P || pause_ss, 'Delete block %s', block);

            bl = mut_op(obj.r, block_parent, this_block,...
                connections, sources, destinations, is_if_block, obj.mutop_args);

            bl.go();

            obj.r.n_live_mutated = obj.r.n_live_mutated + 1;

            emi.pause_interactive(emi.cfg.DELETE_BLOCK_P, 'Block %s Live Mutation completed', block);

        end

        function init(obj)
            %%

            obj.if_target_not_mutated = ones(size(obj.mutant.blocks, 1), 1);

%             obj.if_cond_gen_blocks = obj.mutant.blocks( obj.mutant.blocks.usable_sigRange, :);
                if_con = obj.mutant.blocks( obj.mutant.blocks.usable_sigRange, :);
                obj.if_cond_gen_blocks = if_con(1,:);
                p = 1;
                for i = 1:size(if_con,1)
                    if_con_nam =  cell2mat(if_con{i,'fullname'});
                    if_con_name = [obj.mutant.sys '/' if_con_nam];
                    filter_if = get_param(if_con_name,'PortHandles').Outport;
                    filter_source = get_param(if_con_name,'PortHandles').Inport;
                    if_com_na = strsplit(if_con_nam,'/');
                    if size(filter_if,2) ==1 && size(filter_source,2)>0&&size(if_com_na,2) < 2
                        obj.if_cond_gen_blocks(p,:) = if_con(i,:);
                            p=p+1;
                    end
                end

            % Neither If block nor Action subsystem
            tmp = obj.mutant.blocks.blocktype;
            tmp{1} = '';
            obj.valid_for_if_target = ~startsWith(...
                tmp,...
                {'If', 'Model', 'Delay'}...
                ) &...
                obj.mutant.blocks.not_action;
        end


        function new_block = change_block(obj, block, mut_op)
            %% Change the block before starting mutation.
            % Some mutation ops just cannot mutate any block
            new_block = block;

            if mut_op == 4
                % @emi.live.AlwaysTrue
                % Warning: Currently it applies to both live and dead
                % blocks as no check to skip dead blocks is made.
                new_block = [];


                if isempty(obj.if_cond_gen_blocks)
                    return;
                end
                if_cond_gen_idx = randi(size(obj.if_cond_gen_blocks, 1),1);

                if_cond_generator = obj.if_cond_gen_blocks{if_cond_gen_idx, 'fullname' };

                if_cond_generator = if_cond_generator{1};
                if strcmp(get_param(block, 'blockType'), 'ifaction')
                    obj.l.info('将重新选则模块，此模块无法使用')
                    select_p = {};
                    %%设置一个计数器
                    count = 1;
                    for i = 1:size(obj.if_cond_gen_blocks, 1)
                        select_if = obj.if_cond_gen_blocks{i, 'fullname' };
                        select_if = cell2mat(select_if);
                        sys = obj.r.original_sys;
                        load_system( [getenv('COVEXPEXPLORE') '\' sys])
                        %%
                        line_object = find_system(sys,'FindAll','on','type','line');
                        line = get(line_object);
                        Line_p = {};
                        for j = 1:size(line,1)
                            Line_p{j} = line(j).SrcPortHandle;
                        end
                        new_sys = [sys '/' select_if];
                        dsti = get_param(new_sys,'PortHandles').Outport;
                        for p =1:size(Line_p,2)
                            if size(Line_p{p},1)>1
                                for j =1:size(Line_p{p},1)
                                    if Line_p{p}(j) == dsti(:,1)
                                        new_blk_handle = line(p).DstBlockHandle;
                                        break;
                                    end
                                end
                            else
                                if Line_p{p} == dsti(:,1)
                                    new_blk_handle = line(p).DstBlockHandle;
                                    break;
                                end
                            end
                        end
                        new_block_sys = get_param(new_blk_handle,'blocktype');
                        new_block_prt = get_param(new_blk_handle,'PortHandles').Inport;
                        if ~strcmp(new_block_sys,'ifaction')&&size(new_block_prt,2)<2
                            select_p{count,1} = select_if;
                            count = count+1;
                        end
                    end
                    if_cond_gen_idx = randi(size(select_p, 1),1);

                    if_cond_generator = select_p{if_cond_gen_idx};
                    if_cond_generators = select_p{if_cond_gen_idx};
                    for i =1:size(obj.if_cond_gen_blocks, 1)
                        if strcmp(if_cond_generator,obj.if_cond_gen_blocks{i, 'fullname' })
                            if_cond_gen_idxs = i;
                            break;
                        end
                    end
                    %                     if_cond_generator = if_cond_generator{1};
                    sys = obj.r.original_sys;
                    load_system( [getenv('COVEXPEXPLORE') '\' sys])
                    %%
                    line_object = find_system(sys,'FindAll','on','type','line');
                    line = get(line_object);
                    Line_p = {};
                    for i = 1:size(line,1)
                        Line_p{i} = line(i).SrcPortHandle;
                    end
                    new_sys = [sys '/' if_cond_generator];
                    dsti = get_param(new_sys,'PortHandles').Outport;
                    for i =1:size(Line_p,2)
                        if size(Line_p{i},1)>1
                            for j =1:size(Line{i},1)
                                if Line_p{i}(j) == dsti(:,1)
                                    line(i).DstBlockHandle
                                    new_blk_handle = line(i).DstBlockHandle;
                                    break;
                                end
                            end
                        else
                            if Line_p{i} == dsti(:,1)
                                line(i).SrcBlockHandle
                                new_blk_handle = line(i).DstBlockHandle;
                                break;
                            end
                        end
                    end
                    new_block_sys = get_param(new_blk_handle,'Name');
                    new_block = [obj.mutant.sys '/' new_block_sys];
                else
                    obj.l.info('选择模块暂时可用');
                    sys = obj.r.original_sys;
                    load_system( [getenv('COVEXPEXPLORE') '\' sys])
                    %%
                    line_object = find_system(sys,'FindAll','on','type','line');
                    line = get(line_object);
                    Line = {};
                    for i = 1:size(line,1)
                        Line{i} = line(i).DstPortHandle;
                    end
                    Line_p = {};
                    for i = 1:size(line,1)
                        Line_p{i} = line(i).SrcPortHandle;
                    end
                    block_s = strsplit(block,'/');
                    or_block = [sys '/' block_s{2}];
                    dst = get_param(or_block,'PortHandles').Inport;
                    if size(dst,2)>1
                        dst = dst(:,1);
                    end
                    if size(dst,1) ==0
                        obj.l.info('无接入模块')
                        if_cond_gen_idxs = if_cond_gen_idx;
                        if_cond_generators = if_cond_generator;
                        select_block = true;
                        count = 0;
                        while select_block
                            new_sys = [sys '/' if_cond_generator];
                            dsti = get_param(new_sys,'PortHandles').Outport;
                            for i =1:size(Line_p,2)
                                if size(Line_p{i},1)>1
                                    for j =1:size(Line{i},1)
                                        if Line_p{i}(j) == dsti(:,1)
                                            line(i).DstBlockHandle
                                            new_blk_handle = line(i).DstBlockHandle;
                                            break;
                                        end
                                    end
                                else
                                    if Line_p{i} == dsti(:,1)
                                        line(i).SrcBlockHandle
                                        new_blk_handle = line(i).DstBlockHandle;
                                        break;
                                    end
                                end
                            end
                            new_block_sys = get_param(new_blk_handle,'Name');
                            new_block = [obj.mutant.sys '/' new_block_sys];
                            new_block_ports = get_param(new_blk_handle,'PortHandles').Inport;
                            if size(new_block_ports,2)>1
                                obj.l.info('选择到的模块不正确，将重新进行选择')
                                select_block = true;
                                if_cond_gen_idxs = randi(size(obj.if_cond_gen_blocks, 1),1);

                                if_cond_generator = obj.if_cond_gen_blocks{if_cond_gen_idxs, 'fullname' };

                                if_cond_generator = if_cond_generator{1};
                                if_cond_generators = if_cond_generator;
                            else
                                select_block = false;
                                break;
                            end
                            count = count+1;
                            if count>10
                                obj.l.info('模型不可用，将放弃此模型变体')
                                break;
                            end
                        end
                    else
                        for i =1:size(Line,2)
                            if size(Line{i},1)>1
                                for j =1:size(Line{i},1)
                                    if Line{i}(j) == dst(:,1)
                                        line(i).SrcBlockHandle
                                        ifg_block = line(i).SrcBlockHandle;
                                        break;
                                    end
                                end
                            else
                                if Line{i} == dst(:,1)
                                    line(i).SrcBlockHandle
                                    ifg_block = line(i).SrcBlockHandle;
                                    break;
                                end
                            end
                        end
                        if_cond_generators = get_param(ifg_block,'Name');
                        if_cond_generator_com = obj.if_cond_gen_blocks{:,'fullname'};
                        for i = 1:size(obj.if_cond_gen_blocks, 1)
                            if strcmp(if_cond_generators,if_cond_generator_com{i})
                                if_cond_gen_idxs = i;
                                break
                            end
                        end

                        try
                            isempty(if_cond_gen_idxs)
                            new_block = block;
                        catch
                            obj.l.info('The selected module cannot assume equivalent obligations, and there is no available output range')
                            if_cond_gen_idxs = if_cond_gen_idx;
                            if_cond_generators = if_cond_generator;
                            select_block = true;
                            count = 0;
                            while select_block
                                new_sys = [sys '/' if_cond_generator];
                                dsti = get_param(new_sys,'PortHandles').Outport;
                                for i =1:size(Line_p,2)
                                    if size(Line_p{i},1)>1
                                        for j =1:size(Line_p{i},1)
                                            if Line_p{i}(j) == dsti(:,1)
                                                line(i).DstBlockHandle
                                                new_blk_handle = line(i).DstBlockHandle;
                                                break;
                                            end
                                        end
                                    else
                                        if Line_p{i} == dsti(:,1)
                                            line(i).SrcBlockHandle
                                            new_blk_handle = line(i).DstBlockHandle;
                                            break;
                                        end
                                    end
                                end
                                new_block_ports = get_param(new_blk_handle,'PortHandles').Inport;
                                if size(new_block_ports,2)>1
                                    obj.l.info('选择到的模块不正确，将重新进行选择')
                                    select_block = true;
                                    if_cond_gen_idxs = randi(size(obj.if_cond_gen_blocks, 1),1);

                                    if_cond_generator = obj.if_cond_gen_blocks{if_cond_gen_idxs, 'fullname' };

                                    if_cond_generator = if_cond_generator{1};
                                    if_cond_generators = if_cond_generator;
                                else
                                    select_block = false;
                                    break;
                                end
                                count = count+1;
                                if count>10
                                    obj.l.info('模型不可行，将放弃变体')
                                    break;
                                end
                            end
                            new_block_sys = get_param(new_blk_handle,'Name');
                            new_block = [obj.mutant.sys '/' new_block_sys];
                        end
                    end
                end
                 close_system([getenv('COVEXPEXPLORE') '\' sys]);
                if strcmp(get_param(block, 'blockType'), 'Delay')
% %                 if strcmp(commpare,'Delay')
                    obj.l.info('有容易出现代数环的风险,将予以阻断,请明确条件重新挑选')
                    new_block = '';
                   
%                     [block_parent, ~] = utility.strip_last_split(if_cond_generator, '/');
% 
%                     if ~isempty(block_parent)
%                         block_parent = [block_parent '/'];
%                     end

                % Now select target block which would be mutated. I.e. put
                % in an Action subsystem
                
                
                % Blocks which are in the same subsystem as
                % if_cond_generator. Also cannot be If block or Action
                % Subsystem. And cannot be if_cond_generator itself
%                 
%                 desired_depth = numel(strsplit(if_cond_generator, '/')) + 1;
%                 
%                 candi_blocks = obj.mutant.blocks{...
%                       startsWith(obj.mutant.blocks.fullname, block_parent) &...
%                        obj.mutant.blocks.depth == desired_depth & ...
%                        obj.valid_for_if_target & ...
%                        obj.if_target_not_mutated & ...
%                        ~strcmp(obj.mutant.blocks.fullname, if_cond_generator),...
%                    'fullname'};
%                 if isempty(candi_blocks)
%                     return;
%                 end    
%                      
%                 candi_blk_id = randi(size(candi_blocks, 1),1);
%                 
%                 candi_fname = candi_blocks{candi_blk_id};
%                 true_candi_id = find(strcmp(candi_fname, obj.mutant.blocks.fullname));
%                 
%                 obj.if_target_not_mutated(true_candi_id) = false;
%                 
           
                else
                % Pass args to decorator
                new_block_compare = strsplit(new_block,'/');
                for i = 1:size(obj.mutant.blocks,1)
                 if strcmp(new_block_compare{2},obj.mutant.blocks(i,1).fullname)
                     true_candi_id = i;
                     break;
                 else
                 end
                end
                try
                    true_candi_id
                catch
                    new_block_compare
                end
                % sample time of If cond generator
                %obj.mutant.blocks(true_candi_id, :);
                try
                    % Set the if-block sampling time
                    % to the else branch to include the module sampling time
                    candi_block_st = get_param(new_block,'SampleTime');
                catch
                    %If the module does not support the sampling time, 
                    % it will automatically inherit the previous module
                        candi_block_st = '-1';
                end
                %candi_block_st = '-1';
                if isempty(candi_block_st)
                    candi_block_st = '-1'; 
                end
                
                obj.l.info('ST candi blk name: %s; st: %s',new_block, candi_block_st);
                obj.l.info('If cond generator id: %d, name: %s', if_cond_gen_idx, if_cond_generators);
                
                obj.mutop_args = {...
                    obj.if_cond_gen_blocks(if_cond_gen_idxs, :),...
                    candi_block_st...
                };
                %obj.mutop_args(2) = obj.r.sample_time_st;
                % Update block type
                try
                obj.mutant.blocks.blocktype{true_candi_id} = 'SubSystem';
                obj.mutant.blocks.not_action(true_candi_id) = false;
                catch
                    obj.l.info('选择模块可能发生未知错误请谨慎选择')
                end
                end
            end
        end
        
    end
end

