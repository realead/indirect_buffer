import unittest

from cython cimport view
from cython.view cimport array as cvarray
from indirect_buffer.buffer_impl cimport IndirectMemory2D


class MockMemNanny:
    def __init__(self, lst):
        self.lst=lst

    def __del__(self):
        self.lst.append("Deallocated")


#makes sure there are no references to MockMemNanny-object around
cdef create_with_nanny(void * ptr, lst):
    mem = IndirectMemory2D.from_ptr_with_memory_nanny(ptr,1,1,'i',0, MockMemNanny(lst))
    return mem

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

 
    def test_from_pointer_with_nanny(self):
       cdef int val = 5
       cdef int *ptr = &val
       cdef int **ptr_ptr = &ptr
       lst=[]
       mem = create_with_nanny(<void *>ptr_ptr, lst)
       view = memoryview(mem)
       del mem
       self.assertEqual(len(lst), 0)
       del view
       self.assertEqual(len(lst), 1)


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


    def test_copy_from_to_clayout(self):
       orig = view.array(shape=(42, 32), itemsize=sizeof(int), format="i", mode="c")
       copy = view.array(shape=(42, 32), itemsize=sizeof(int), format="i", mode="c")
       mem = IndirectMemory2D.create(42,32,'i',0)
       orig[11, 25] = 42
       mem.copy_from(orig)
       mem.copy_to(copy)
       self.assertEqual(copy[11, 25], 42) 


    def test_copy_from_to_fortranlayout(self):
       orig = view.array(shape=(42, 32), itemsize=sizeof(int), format="i", mode="fortran")
       copy = view.array(shape=(42, 32), itemsize=sizeof(int), format="i", mode="fortran")
       mem = IndirectMemory2D.create(42,32,'i',0)
       orig[11, 25] = 42
       mem.copy_from(orig)
       mem.copy_to(copy)
       self.assertEqual(copy[11, 25], 42)    


    def test_copy_from_fortranlayout_to_clayout(self):
       orig = view.array(shape=(42, 32), itemsize=sizeof(int), format="i", mode="fortran")
       copy = view.array(shape=(42, 32), itemsize=sizeof(int), format="i", mode="c")
       mem = IndirectMemory2D.create(42,32,'i',0)
       orig[11, 25] = 42
       mem.copy_from(orig)
       mem.copy_to(copy)
       self.assertEqual(copy[11, 25], 42)    


    def test_copy_from_clayout_to_fortranlayout(self):
       orig = view.array(shape=(42, 32), itemsize=sizeof(int), format="i", mode="c")
       copy = view.array(shape=(42, 32), itemsize=sizeof(int), format="i", mode="fortran")
       mem = IndirectMemory2D.create(42,32,'i',0)
       orig[11, 25] = 42
       mem.copy_from(orig)
       mem.copy_to(copy)
       self.assertEqual(copy[11, 25], 42) 


    def test_view_from_rows(self):
        import numpy as np
        a =  np.zeros((7,4), order="C")
        a[1,2] = 21
        a[2,1] = 42
        mem  = IndirectMemory2D.cy_view_from_rows(a)
        self.assertEqual(mem.shape[0], 7)
        self.assertEqual(mem.shape[1], 4)
        self.assertEqual(memoryview(mem)[1,2], 21)
        self.assertEqual(memoryview(mem)[2,1], 42)
        memoryview(mem)[1,3] = 5
        memoryview(mem)[3,1] = 6
        self.assertEqual(a[1,3], 5)
        self.assertEqual(a[3,1], 6) 


    def test_view_from_cols(self):
        import numpy as np
        a =  np.zeros((4,7), order="F")
        a[1,2] = 21
        a[2,1] = 42
        mem  = IndirectMemory2D.cy_view_from_columns(a)
        self.assertEqual(mem.shape[0], 7) #dimensions swapped
        self.assertEqual(mem.shape[1], 4) #dimensions swapped
        self.assertEqual(memoryview(mem)[1,2], 42) #dimensions swapped
        self.assertEqual(memoryview(mem)[2,1], 21) #dimensions swapped
        memoryview(mem)[1,3] = 5
        memoryview(mem)[3,1] = 6
        self.assertEqual(a[1,3], 6)  #dimensions swapped
        self.assertEqual(a[3,1], 5)  #dimensions swapped  




