import unittest

from cython cimport view
from indirect_buffer.buffer_impl cimport IndirectMemory2D


class IndirectMemoryTester(unittest.TestCase): 
    def test_create(self):
        mem = IndirectMemory2D.create(5,6,b'i',0)
        cdef int **ptr = mem.as_int_ptr_ptr()
        self.assertEqual(ptr[4][5], 0)


    def test_create_getbuffer(self):
        mem = IndirectMemory2D.create(5,6,b'i',0)
        cdef int[::view.indirect_contiguous, ::1] data = mem
        data[4,3]=42
        cdef int **ptr = mem.as_int_ptr_ptr()
        self.assertEqual(ptr[4][3], 42)


    def test_create_readonly_ok(self):
        mem = IndirectMemory2D.create(5,6,b'i',1)
        self.assertEqual(mem.readonly, 1)
        cdef const int[::view.indirect_contiguous, ::1] data = mem
        self.assertEqual(data[4][3], 0)


    def test_create_readonly_throw(self):
        mem = IndirectMemory2D.create(5,6,b'i',1)
        self.assertEqual(mem.readonly, 1)
        cdef int[::view.indirect_contiguous, ::1] data
        with self.assertRaises(BufferError) as context:
            data = mem
        self.assertEqual("buffer is not writable", context.exception.args[0])


    def test_create_getbuffer_memoryview(self):
        mem = IndirectMemory2D.create(5,6,b'i',0)
        data = memoryview(mem)
        data[4,5]=42
        cdef int **ptr = mem.as_int_ptr_ptr()
        self.assertEqual(ptr[4][5], 42)

    def test_from_pointer(self):
       cdef int val = 5
       cdef int *ptr = &val
       cdef int **ptr_ptr = &ptr
       mem = IndirectMemory2D.from_ptr(<void *>ptr_ptr,1,1,'i',0)
       self.assertEqual(mem.as_int_ptr_ptr()[0][0], 5)


    def test_from_pointer_getbuffer(self):
       cdef int val = 5
       cdef int *ptr = &val
       cdef int **ptr_ptr = &ptr
       mem = IndirectMemory2D.from_ptr(<void *>ptr_ptr,1,1,'i',0)
       cdef int[::view.indirect_contiguous, ::1] data = mem
       data[0][0]=42
       self.assertEqual(val, 42)


    def test_getbuffer_throw_if_not_indirect(self):
       mem = IndirectMemory2D.create(5,6,b'i',0)
       cdef int[::view.strided, ::view.strided] data
       with self.assertRaises(BufferError) as context:
            data = mem

       self.assertTrue('need PyBUF_INDIRECT-able buffer-consumer' in str(context.exception))

 
    def test_from_pointer_readonly_ok(self):
       cdef int val = 5
       cdef int *ptr = &val
       cdef int **ptr_ptr = &ptr
       mem = IndirectMemory2D.from_ptr(<void *>ptr_ptr,1,1,'i',1)
       cdef const int[::view.indirect_contiguous, ::1] data = mem
       self.assertEqual(data[0][0], 5)


    def test_from_pointer_readonly_throw(self):
       cdef int val = 5
       cdef int *ptr = &val
       cdef int **ptr_ptr = &ptr
       mem = IndirectMemory2D.from_ptr(<void *>ptr_ptr,1,1,'i',1)
       cdef int[::view.indirect_contiguous, ::1] data
       with self.assertRaises(BufferError) as context:
            data = mem
       self.assertEqual("buffer is not writable", context.exception.args[0])       




