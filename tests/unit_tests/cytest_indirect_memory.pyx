import unittest

from indirect_buffer.buffer_impl cimport IndirectMemory2D


class IndirectMemoryTester(unittest.TestCase): 
    def test_create(self):
        mem = IndirectMemory2D.create(5,6,4)
        cdef int **ptr = mem.as_int_ptr_ptr()
        self.assertEqual(ptr[4][5], 0)

    def test_from_pointer(self):
       cdef int val = 5
       cdef int *ptr = &val
       cdef int **ptr_ptr = &ptr
       mem = IndirectMemory2D.from_ptr(<void *>ptr_ptr, 1,1,4)
       self.assertEqual(mem.as_int_ptr_ptr()[0][0], 5)
