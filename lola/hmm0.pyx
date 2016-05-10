"""
This is a cython implementation of zeroth-order HMM alignment models (e.g. IBM1 and IBM2).

:Authors: - Wilker Aziz
"""

"""
# cython: boundscheck=False
# cython: wraparound=False
# cython: cdivision=True
# cython: nonecheck=False
"""

import numpy as np
cimport numpy as np
cimport cython
import sys
import logging

from lola.corpus cimport Corpus
from lola.component cimport GenerativeComponent
from lola.model cimport GenerativeModel, SufficientStatistics, ExpectedCounts


cpdef float viterbi_alignments(Corpus e_corpus, Corpus f_corpus, GenerativeModel model, ostream=sys.stdout):
    """
    This writes Viterbi alignments to an output stream.

    :param e_corpus:
    :param f_corpus:
    :param lex_parameters:
    :param ostream: output stream
    """
    cdef:
        size_t S = f_corpus.n_sentences()
        size_t s
        np.int_t[::1] f_snt, e_snt
        np.int_t[::1] alignment
        size_t i, j, best_i
        int f, e
        float p, best_p

    for s in range(S):
        f_snt = f_corpus.sentence(s)
        e_snt = e_corpus.sentence(s)
        alignment = np.zeros(len(f_snt), dtype=np.int)
        for j in range(len(f_snt)):
            best_i = 0
            best_p = 0
            for i in range(len(e_snt)):
                p = model.posterior(e_snt, f_snt, i, j)
                # introduced a deterministic tie-break heuristic that dislikes null-alignments
                if p > best_p:
                    best_p = p
                    best_i = i
            alignment[j] = best_i
        # in printing we make the French sentence 1-based by convention
        # we keep the English sentence 0-based because of the NULL token
        print(' '.join(['{0}-{1}'.format(i, j + 1) for j, i in enumerate(alignment)]), file=ostream)


cpdef float loglikelihood(Corpus e_corpus, Corpus f_corpus, GenerativeModel model):
    """
    Computes the log-likelihood of the data under IBM 1 for given parameters.

    :param e_corpus: an instance of Corpus (with NULL tokens)
    :param f_corpus: an instance of Corpus (without NULL tokens)
    :param lex_parameters: a collection of |V_E| categoricals over the French vocabulary V_F
    :return: log of \prod_{f_1^m,e_0^l} \prod_{j=1}^m \sum_{i=0}^l lex(f_j|e_i)
    """
    cdef:
        float loglikelihood = 0.0
        size_t S = f_corpus.n_sentences()
        np.int_t[::1] f_snt, e_snt
        size_t s, i, j
        int e, f
        float p

    for s in range(S):
        f_snt = f_corpus.sentence(s)
        e_snt = e_corpus.sentence(s)
        for j in range(len(f_snt)):
            p = 0.0
            for i in range(len(e_snt)):
                p += model.likelihood(e_snt, f_snt, i, j)
            loglikelihood += np.log(p)

    return loglikelihood


cpdef float empirical_cross_entropy(Corpus e_corpus, Corpus f_corpus, GenerativeModel model, float log_zero=-99):
    """
    Computes H(p*, p) = - 1/N \sum_{s=1}^N p(f^s|e^s)
        where p is a model distribution
        p* is the unknown true distribution
        and we have N iid samples.

    Note that perplexity can be obtained by computing 2^H(p*,p).

    :param e_corpus: an instance of Corpus (with NULL tokens)
    :param f_corpus: an instance of Corpus (without NULL tokens)
    :param model: a probability model
    :return: H(p*, p)
    """
    cdef:
        float log_p_s
        float entropy = 0.0
        size_t S = f_corpus.n_sentences()
        np.int_t[::1] f_snt, e_snt
        size_t s, i, j
        int e, f
        float p

    for s in range(S):
        f_snt = f_corpus.sentence(s)
        e_snt = e_corpus.sentence(s)
        log_p_s = 0.0
        for j in range(len(f_snt)):
            p = 0.0
            for i in range(len(e_snt)):
                p += model.likelihood(e_snt, f_snt, i, j)
            if p == 0:  # entropy is typically computed for test sets as well, where some words can be unknown
                log_p_s += log_zero
            else:
                log_p_s += np.log(p)
        entropy += log_p_s

    return - entropy / S


cpdef tuple EM(Corpus e_corpus, Corpus f_corpus, int iterations, GenerativeModel model):
    """
    MLE estimates via EM for zeroth-order HMMs.

    :param e_corpus: an instance of Corpus (with NULL tokens)
    :param f_corpus: an instance of Corpus (without NULL tokens)
    :param iterations: a number of iterations
    :param model_type: reserved for future use (e.g. IBM1, IBM2, VogelIBM2, HMM)
    :param viterbi: whether or not to print Viterbi alignments after optimisation
    :return: model, entropy log
    """
    cdef size_t iteration
    cdef float H = empirical_cross_entropy(e_corpus, f_corpus, model)
    logging.info('I=%d H=%f', 0, H)
    cdef list entropy_log = [H]

    for iteration in range(iterations):
        suffstats = e_step(e_corpus, f_corpus, model)
        m_step(model, suffstats)
        H = empirical_cross_entropy(e_corpus, f_corpus, model)
        entropy_log.append(H)
        logging.info('I=%d H=%f', iteration + 1, H)

    return model, entropy_log


cdef ExpectedCounts e_step(Corpus e_corpus, Corpus f_corpus, GenerativeModel model):
    """
    The E-step gathers expected/potential counts for different types of events updating
    the sufficient statistics.

    IBM1 uses lexical events only.
    IBM2 uses lexical envents and distortion events.

    :param e_corpus:
    :param f_corpus:
    :param model: a zeroth-order HMM
    :param suffstats: a sufficient statistics object compatible with the model
    """

    cdef ExpectedCounts suffstats = <ExpectedCounts> model.suffstats()
    cdef size_t S = f_corpus.n_sentences()
    cdef np.int_t[::1] f_snt, e_snt
    cdef np.float_t[::1] posterior_aj
    cdef size_t s, i, j
    cdef int f, e

    for s in range(S):
        f_snt = f_corpus.sentence(s)
        e_snt = e_corpus.sentence(s)

        # Remember, this is our model
        #   P(f_1^m a_1^m, m|e_0^l) \propto \prod_{j=1}^m P(a_j|m,l) \times P(f_j|e_{a_j})
        # Under IBM models 1 and 2, alignments are independent of one another,
        # thus the posterior of alignment links factorise
        #   P(a_1^m|e_0^l, f_1^m) \propto \prod_{j=1}^m P(a_j|e_0^l, f_1^m)
        # where
        #   P(a_j=i|e_0^l, f_1^m) \propto P(a_j=i|m,l) \times P(f_j|e_i)
        # If this is IBM model 1,
        #   then the first term is a constant (uniform probability over alignments)
        #    which can therefore be ignored (due to proportionality)
        #   and the second term is a lexical Categorical distribution
        # IBM 1:
        #   P(a_j=i|e_0^l,f_1^m) \propto lex(f_j|e_i)

        # Observe that the posterior for a candidate alignment link is a distribution over assignments of a_j=i
        # That is, a French *position* j being aligned to an English *position* i.
        # For a given French position j, I am choosing to represent it by a vector indexed by English positions
        # Thus a cell posterior_aj[i] is associated with P(a_j=i|e_0^l,f_1^m)

        for j in range(len(f_snt)):
            f = f_snt[j]
            posterior_aj = np.zeros(len(e_snt))

            # To compute the probability of each outcome of a_j
            # we start by evaluating the numerator of P(a_j=i|e_0^l,f_1^m) for every possible i
            for i in range(len(e_snt)):
                e = e_snt[i]
                # if this was IBM 2, we would also have the contribution of a distortion parameter
                posterior_aj[i] = model.posterior(e_snt, f_snt, i, j)
            # Then we normalise it making a proper cpd
            posterior_aj /= np.sum(posterior_aj)

            # Once the (normalised) posterior probability of each outcome has been computed
            #  we can easily gather partial counts
            for i in range(len(e_snt)):
                #e = e_snt[i]
                #lex_counts.plus_equals(e, f, posterior_aj[i])
                suffstats.observation(e_snt, f_snt, i, j, posterior_aj[i])
                # if this was IBM2, we would also accumulate dist_counts.plus_equals(i, j, posterior_aj[i])

        #if (s + 1) % 10000 == 0:
        #    logging.debug('E-step %d/%d sentences', s + 1, S)
    return suffstats


cpdef m_step(GenerativeModel model, ExpectedCounts suffstats):
    """
    The M-step normalises the sufficient statistics for each event type and construct a new model.
    """
    cdef GenerativeComponent comp
    for comp in suffstats.components():
        comp.normalise()
    model.update(suffstats.components())


