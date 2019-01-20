import unittest

from cython cimport view
from indirect_buffer.buffer_impl cimport BufferCollection2D


class BufferCollection2DTester(unittest.TestCase): 
    def test_create(self):
        arr1=bytearray(b'aa')
        arr2=bytearray(b'bb')
        mem = BufferCollection2D([arr1, arr2])
        cdef char[::view.indirect_contiguous, ::1] data = mem
        self.assertEqual(data[0][0], ord('a'))
        data[1][1]=ord('c')
        self.assertEqual(arr2[1], ord('c'))
