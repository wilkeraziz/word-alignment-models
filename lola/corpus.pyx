cimport numpy as np
import numpy as np


cdef tuple tokenize(istream, bos=None):
    """
    This method tokenizes an input corpus and returns a stream of tokens.

    :param istream: input stream (e.g. file handler)
    :param bos: this is optional and if set it is added to the beginning of every sentence
    :return: an np.array of tokens, and an np.array of boundary positions
    """
    cdef str line
    cdef list tokens = []
    cdef list boundaries = []
    if bos:
        for line in istream:
            tokens.append(bos)
            tokens.extend(line.split())
            boundaries.append(len(tokens))
    else:
        for line in istream:
            tokens.extend(line.split())
            boundaries.append(len(tokens))
    return np.array(tokens, dtype='U'), np.array(boundaries, dtype=np.int)


cdef class Corpus:
    """
    A corpus is a collection of sentences.
    Each sentence is a sequence of words.

    Internally, words are represented as integers for compactness and quick indexing using numpy arrays.

    Remark: This object offers no guarantee as to which exact index any word will get. Not even the NULL word.
    """

    def __init__(self, istream, null=None):
        """
        Creates a corpus from a text file.
        The corpus is internally represented by a flat numpy array.

        :param istream: an input stream or a path to a file
        :param null: an optional NULL token to be added to the beginning of every sentence
        """

        # read and tokenize the entire corpus
        # and if a null symbol is given, we place it at the beginning of the sentence
        # we also memorise the boundary positions
        if type(istream) is str:  # this is actually a path to a file
            with open(istream, 'r') as fstream:
                tokens, self._boundaries = tokenize(fstream, bos=null)
        else:
            tokens, self._boundaries = tokenize(istream, bos=null)
        # use numpy to map tokens to integers
        # lookup converts from integers back to strings
        # inverse represents the corpus with words represented by integers
        self._lookup, self._inverse = np.unique(tokens, return_inverse=True)

    cpdef np.int_t[::1] sentence(self, size_t i):
        """
        Return the ith sentence. This is not checked for out-of-bound conditions.
        :param i: 0-based sentence id
        :return: memory view corresponding to the sentence
        """
        cdef size_t a = 0 if i == 0 else self._boundaries[i - 1]
        cdef size_t b = self._boundaries[i]
        return self._inverse[a:b]

    def itersentences(self):
        """Iterates over sentences"""
        cdef size_t a = 0
        cdef size_t b
        for b in self._boundaries:
            yield self._inverse[a:b]  # this produces a view, not a copy ;)
            a = b

    cpdef translate(self, size_t i):
        """
        Translate an integer back to a string.
        :param i: index representing the word
        :return: original string
        """
        return self._lookup[i]

    cpdef size_t vocab_size(self):
        """Number of unique tokens (if the corpus was created with added NULL tokens, this will include it)"""
        return self._lookup.size

    cpdef size_t corpus_size(self):
        """Number of tokens in the corpus."""
        return self._inverse.size

    cpdef size_t n_sentences(self):
        """Number of sentences in the corpus."""
        return self._boundaries.size
