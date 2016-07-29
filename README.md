
This project is about feature-rich unsupervised word alignment models.
At this point we are working on 0th order HMMs, that is, IBM2-like models.
We follow Berg-Kirkpatrick et al (2010) and reparameterise IBM2's categorical distributions using exponentiated linear functions (a log-linear parameterisation).

This code-base started as Guido Linder's final project towards his BSc.

# Build

Check our [build](doc/build.md) instructions.
        

# Examples

You can try:

    # here we train a model using a training corpus and use it to obtain Viterbi alignments
    time python -m lola.aligner -f training/example.f -e training/example.e -v --ibm1 5 --ibm2 5  --viterbi training/training --save-entropy training/training.entropy

    # here we train a model using a training corpus and use it to obtain Viterbi alignments to both training and test sets
    time python -m lola.aligner -f training/example.f -e training/example.e -v --ibm1 5 --ibm2 5 --test-f training/example.test.f --test-e training/example.test.e  --viterbi training/example --save-entropy training/example.entropy

    # here we train a model using the concatenation of training and test sets (this is basically to avoid OOVs) and use it to obtain Viterbi alignments to both training and test sets
    # note that it is okay to concatenate the sets because the task remains unsupervised and in normal uses there is no such a distinction between training and test sets, this distinction only makes sense when we are interested in computing AER for the test set based on some manual alignments
    time python -m lola.aligner -f training/example.f -e training/example.e -v --ibm1 5 --ibm2 5 --test-f training/example.test.f --test-e training/example.test.e --merge  --viterbi training/merged --save-entropy training/merged.entropy


    # current interface
    time python -m lola.aligner debug/5k -f training/5k.f -e training/5k.e -v --ibm1 3 --ibm2 2 --test-f training/fr-en/testing/test/test.f --test-e training/fr-en/testing/test/test.e --merge --viterbi --save-parameters --naacl --posterior --save-entropy --skip-null

* the first value is the output directory
* then we have chosen a training set
* a few iterations of ibm1 and ibm2
* a test set
* we decided to merge training and test to avoid OOVs
* we decided to save the viterbi alignments
* to save the parameters of the model (after EM)
* and to save alignments also in NAACL format
* in NAACL format we can also have the posterior probability of each alignment
* we are saving the entropy of EM iterations
* and we are not printing alignments to NULL (the model does align things to NULL, we just do not print it)

For an example of feature extraction check

    python -m lola.extractor


# Config files

The configuration file has 3 blocks.

## Extractors

The block `[extractors]` can be used to configure feature extractor objects.
You should start by naming the extractor (e.g. words), then separate the name from the configuration with a colon ':'.
Then, choose the extractor type (e.g. WholeWordFeatures, this is a class in lola.ff).
After that, provide key-value pairs for the configuration of the extractor (each extractor knows how to configure itself give a string of key-value pairs). 
These key-value pairs are evaluated literally using python's eval function.
For now, we do not support spaces in the value, thus be careful with that, for example if you need a list with two numbers use [2,3] as opposed to [2, 3].
A few examples of extractors:


    [extractors]
    words: type=WholeWordFeatures extract_e=True extract_f=True extract_ef=True
    affixes: type=AffixFeatures extract_e=False extract_f=False extract_ef=True suffix_sizes=[2,3] prefix_sizes=[]
    categories: type=CategoryFeatures extract_e=True extract_f=True extract_ef=True 


You can repeat extractors of a given type, as long as you name them uniquely, example:


    [extractors]    
    suffixes: type=AffixFeatures extract_e=False extract_f=False extract_ef=True suffix_sizes=[2,3] prefix_sizes=[]
    prefixes: type=AffixFeatures extract_e=True extract_f=False extract_ef=False suffix_sizes=[] prefix_sizes=[2]


## Components

The second block `[components]` is used to configure locally normalised components of several types.
Again, you should start by naming a component (e.g. lexical), then separate the name from the configuration with a colon ':'.
Then, choose the component's type (e.g. BrownLexical).
Finally, provide key-value pairs for the configuration of the component.

Examples of multinomial/categorical components:


    [components]
    lexical: type=BrownLexical
    udist: type=UniformAlignment
    jump: type=VogelJump


Examples of log-linear components:


    [components]
    llLexical: type=LogLinearLexical init='uniform' sgd-steps=5 sgd-attempts=10 extractors=['categories','words']


Note that the log-linear component uses two of the feature extractors declared in the first block.
Also, log-linear components are optimised by SGD, thus we note some SGD options being configured.


## Models

Finally, the block `[models]` is used to specify full models (made of sets of components).
First, name your model (e.g. ibm1). Then, to define this model, specify a list of unique components with they mandatory keyword 'components='.
Also, to decide for how long we should optimise this model with EM, specify the mandatory keyword 'iterations='.

Examples:


    [models]

    ibm1: iterations=5 components=['lexical','udist']
    ibm2: iterations=5 components=['lexical','jump']


Note that we can have multiple models. They are optimised in the given order (in this case `ibm1` first, then `ibm2`).
They may reuse certain components, in which case higher models benefit from previously optimised components from lower models.
In the example, `ibm2` reuses the lexical component previously trained with `ibm1`, but replaces IBM1's uniform distortion by jump-based distortion.


# Using config files

        
        python -m lola.aligner training/ibm2.ini debug/ibm2 -f training/example.f -e training/example.e --save-entropy --save-parameters -v
        python -m lola.aligner training/llibm2.ini debug/llibm2 -f training/example.f -e training/example.e --save-entropy --save-parameters -v


# Examples


        # Download some data
        wget https://www.adrive.com/public/YVKseV/wa.tgz
