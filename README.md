# SLBug-Hunter
## [SLBug-Hunter:New Simulink Test Tool](https://github.com/EDA-Testing/SLBug-Hunter/edit/master/README.md)
**Matlab env dependencies:**
1. **Matlab 2021b**
2. **Simulink default**
***
### Datatest:
If you wish to use publicly available datasets, you can access *[third-party datasets](https://drive.google.com/drive/folders/173ik08oi3BCnPzjlZkHYhMAkp93zW-V4?usp=sharing)*. If you wish to use a random model, 
you can visit *[Dr. Shafiul's homepage](https://github.com/verivital/slsf_randgen/wiki)*. Get the latest experimental model generation tools SLFORGE/CYFUZZ

##### [SLforge: Automatically Finding Bugs in a Commercial Cyber-Physical Systems Development Tool](https://github.com/verivital/slsf_randgen/wiki#getting-slforge)
**The format of the model is divided into mdl and slx according to the Simulink standard. If you use some third-party open source models, make sure that the dependencies 
between the models and the data are loaded into your memory. We do not recommend using third-party models in unfiltered conditions, which will cause your computer
to crash abnormally. Please be careful**
***
### Our Works
We are committed to testing the stability of the `CPS` ` (cyber physical systems)` development tool Simulink. Our work mainly relies on the live mutation technique to detect Simulink bugs by means of `Equivalent Modulo Input` `(EMI)`. We will first obtain the information of the test model, including the number of modules of the model, the coverage ratio, the input and output information of the module, the handle of the module and its connection, etc. The mutation testing step is performed based on the obtained model information. We add the conditional discriminant module to the random selection module, and synthesize discriminants with contradictory predicates according to the input and output information. Then another module in the model is selected according to our specific discriminant method to be added to the branch where the discriminant module is always executed. In branches that are not executed, we will synthesize new regions according to our method. This results in a variant model. Finally compare the variant with the original model to discover potential flaws in Simulink

***
### Hello World
Before starting, you need to set two environment variables `SLSFCORPUS` and `COVEXPXPLORE`,both of which point to your `reproduce/samplecorpus` file. In subsequent operations, you need to put the test models into 
this folder so that Simulink can quickly and accurately find the files you need

If you have questions about setting environment variables, please visit the official *[Mathworks website](https://ww2.mathworks.cn/help/matlab/ref/setenv.html?lang=en)*
***
In order to test the stability of the program, you need to test and collect the coverage information of the model in advance. You need to run this at the Matlab command line：

```covexp.covcollect```

You can change the collected configuration parameters in the file `covcfg.m` and set the maximum compile time for the model
Due to problems with some models, this process may experience program termination. 
If you wish, you can choose in the file.Replace  `@emi.preprocess_models` with `@emi.check_SLforge` . Also replace the path in the file with the absolute path where you store the model file
This will help you filter your models

***
### Test Program
**Warning: You must collect coverage information before running the compiled test program.**
You can modify the parameters of the mutation in the `cfg.m` file, including the number of variants, the rate of variants, and the choice of variant space.
Once everything is in place, you can run in the Matlab command line:

```emi.go()```

A mutation procedure for variants is performed.

****
### Test Result
The experimental results will be placed in the +emi_result file, and the information including the variants will also be written separately into the `.mat` data table of each 
variant subfile. If you want to see the overall data, you can run from the Matlab command line:
```emi.repoert```

***
**Thanks to MathWorks consultants Zouyi Yang, Lily Yan and Finao Peng for their support. We got a lot of help from MathWorks staff in the discovery and confirmation of bugs, and we can't list them all. I would like to express my gratitude here.**
