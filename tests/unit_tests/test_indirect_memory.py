# the actual test is in the cython module
import sys
import unittest
import pyximport; pyximport.install(language_level=sys.version_info[0], build_dir="temp_builds")
from cytest_indirect_memory import *

import ctypes
import array

from indirect_buffer.buffer_impl import IndirectMemory2D



class IndirectMemory2D2DPurePython(unittest.TestCase):

    def test_from_ctype_ptr_1d(self):
         data=(ctypes.c_double*2)(1.0,2.0)
         with self.assertRaises(BufferError) as context:
            mem = IndirectMemory2D.from_ctype_ptr(data, 2,0)
         self.assertTrue("wrong format: b'" in context.exception.args[0]) 


    def test_tfrom_ctype_ptr_3d(self):
         data=(ctypes.POINTER(ctypes.POINTER(ctypes.c_int))*3)()
         with self.assertRaises(BufferError) as context:
            mem = IndirectMemory2D.from_ctype_ptr(data, 3,0)
         self.assertTrue("wrong format: b'" in context.exception.args[0]) 


    def test_from_ctype_ptr_wrong_row_number(self):
         data=(ctypes.POINTER(ctypes.c_int)*2)((ctypes.c_int*1)(1), (ctypes.c_int*1)(1))
         with self.assertRaises(BufferError) as context:
            mem = IndirectMemory2D.from_ctype_ptr(data, 3,1)
         self.assertEqual("less rows than expected: 2 vs. 3", context.exception.args[0]) 


    def test_from_ctype_ptr_less_rows_ok(self):
         data=(ctypes.POINTER(ctypes.c_int)*3)((ctypes.c_int*1)(42), (ctypes.c_int*1)(1), (ctypes.c_int*1)(1))
         mem = IndirectMemory2D.from_ctype_ptr(data, 2,1)
         mem.reinterpret_data('i')
         view=memoryview(mem)
         self.assertEqual(view[0, 0], 42)
         view[0, 0] =  21
         self.assertEqual(data[0] [0], 21) 


    def test_from_ctype_ptr_ptr_is_alive(self):
         data=(ctypes.POINTER(ctypes.c_int)*3)((ctypes.c_int*1)(42), (ctypes.c_int*1)(1), (ctypes.c_int*1)(1))
         ref_cnt = sys.getrefcount(data)
         mem = IndirectMemory2D.from_ctype_ptr(data, 2,1)
         self.assertEqual(ref_cnt+1, sys.getrefcount(data))
         del mem 
         self.assertEqual(ref_cnt, sys.getrefcount(data))


    def test_get_format(self):
        mem = IndirectMemory2D.create_memory(rows=22, cols=33, format='i', readonly=True)
        self.assertEqual(mem.get_format(), b'i')


    def test_reinterpret_locked(self):
        mem = IndirectMemory2D.create_memory(rows=1, cols=1, format='b', readonly=True)
        memview = memoryview(mem)
        # ok, because the same
        mem.reinterpret_data('b')
        self.assertTrue(True)
        #not ok
        with self.assertRaises(BufferError) as context:
            mem.reinterpret_data('B')

        self.assertEqual("buffer is locked", context.exception.args[0])


    def test_reinterpret_signed_unsigned(self):
        mem = IndirectMemory2D.create_memory(rows=1, cols=1, format='b', readonly=False)
        memview = memoryview(mem)
        memview[0,0] = -1      
        del memview

        mem.reinterpret_data('B')
        memview=memoryview(mem)
        self.assertEqual(memview[0,0], 255)



    def test_shape(self):
        mem = IndirectMemory2D.create_memory(rows=42, cols=21, format='b', readonly=False)
        shape = mem.shape
        self.assertEqual(len(shape), 2)
        self.assertEqual(shape[0],42)
        self.assertEqual(shape[1],21)



#### copying part

## copy_from
    def test_readonly_copy_from(self):      
        mem  = IndirectMemory2D.create_memory(rows=1, cols=2, format='B', readonly=True)
        mem2 = IndirectMemory2D.create_memory(rows=1, cols=2, format='B', readonly=False)
        with self.assertRaises(BufferError) as context:
            mem.copy_from(mem2)
        self.assertEqual("copying to readonly buffer", context.exception.args[0])


    def test_copy_from_wrong_dim(self):      
        mem  = IndirectMemory2D.create_memory(rows=1, cols=2, format='B', readonly=False)
        mem2 = bytearray(b'a')
        with self.assertRaises(BufferError) as context:
            mem.copy_from(mem2)
        self.assertEqual("wrong number of dimensions: expected 2, received 1", context.exception.args[0])
        

    def test_copy_from_wrong_shape_cols(self):      
        mem  = IndirectMemory2D.create_memory(rows=1, cols=2, format='B', readonly=False)
        mem2 = IndirectMemory2D.create_memory(rows=1, cols=3, format='B', readonly=False)
        with self.assertRaises(BufferError) as context:
            mem.copy_from(mem2)
        self.assertEqual("different shapes", context.exception.args[0])
        

    def test_copy_from_wrong_shape_rows(self):      
        mem  = IndirectMemory2D.create_memory(rows=1, cols=2, format='B', readonly=False)
        mem2 = IndirectMemory2D.create_memory(rows=2, cols=2, format='B', readonly=False)
        with self.assertRaises(BufferError) as context:
            mem.copy_from(mem2)
        self.assertEqual("different shapes", context.exception.args[0])


    def test_diff_formats_without_cast(self):
        mem  = IndirectMemory2D.create_memory(rows=1, cols=2, format='B', readonly=False)
        mem2 = IndirectMemory2D.create_memory(rows=1, cols=2, format='b', readonly=False)
        with self.assertRaises(BufferError) as context:
            mem.copy_from(mem2)
        self.assertEqual("different formats", context.exception.args[0])


    def test_diff_formats_with_cast(self):
        mem  = IndirectMemory2D.create_memory(rows=1, cols=2, format='B', readonly=False)
        mem2 = IndirectMemory2D.create_memory(rows=1, cols=2, format='b', readonly=False)
        mem.copy_from(mem2, cast=True)
        self.assertTrue(True)

    def test_diff_itemsize_with_cast(self):
        mem  = IndirectMemory2D.create_memory(rows=1, cols=2, format='B', readonly=False)
        mem2 = IndirectMemory2D.create_memory(rows=1, cols=2, format='i', readonly=False)
        with self.assertRaises(BufferError) as context:
            mem.copy_from(mem2, cast=True)
        self.assertEqual("different itemsizes", context.exception.args[0])


    def test_copy_from_indirect_memory(self):
        mem  = IndirectMemory2D.create_memory(rows=42, cols=21, format='i', readonly=False)
        mem2 = IndirectMemory2D.create_memory(rows=42, cols=21, format='i', readonly=False)
        memoryview(mem2)[15,2] = 42
        mem.copy_from(mem2)
        self.assertEqual(memoryview(mem)[15,2], 42)



## copy_to 
    def test_copy_to_readonly(self):      
        mem  = IndirectMemory2D.create_memory(rows=1, cols=2, format='B', readonly=False)
        mem2 = IndirectMemory2D.create_memory(rows=1, cols=2, format='B', readonly=True)
        with self.assertRaises(BufferError) as context:
            mem.copy_to(mem2)
        self.assertEqual("copying to readonly buffer", context.exception.args[0])


    def test_copy_to_wrong_dim(self):      
        mem  = IndirectMemory2D.create_memory(rows=1, cols=2, format='B', readonly=False)
        mem2 = bytearray(b'a')
        with self.assertRaises(BufferError) as context:
            mem.copy_to(mem2)
        self.assertEqual("wrong number of dimensions: expected 2, received 1", context.exception.args[0])
        

    def test_copy_to_wrong_shape_cols(self):      
        mem  = IndirectMemory2D.create_memory(rows=1, cols=2, format='B', readonly=False)
        mem2 = IndirectMemory2D.create_memory(rows=1, cols=3, format='B', readonly=False)
        with self.assertRaises(BufferError) as context:
            mem.copy_to(mem2)
        self.assertEqual("different shapes", context.exception.args[0])
        

    def test_copy_to_wrong_shape_rows(self):      
        mem  = IndirectMemory2D.create_memory(rows=1, cols=2, format='B', readonly=False)
        mem2 = IndirectMemory2D.create_memory(rows=2, cols=2, format='B', readonly=False)
        with self.assertRaises(BufferError) as context:
            mem.copy_to(mem2)
        self.assertEqual("different shapes", context.exception.args[0])


    def test_diff_formats_without_cast_to(self):
        mem  = IndirectMemory2D.create_memory(rows=1, cols=2, format='B', readonly=False)
        mem2 = IndirectMemory2D.create_memory(rows=1, cols=2, format='b', readonly=False)
        with self.assertRaises(BufferError) as context:
            mem.copy_to(mem2)
        self.assertEqual("different formats", context.exception.args[0])


    def test_diff_formats_with_cast_to(self):
        mem  = IndirectMemory2D.create_memory(rows=1, cols=2, format='B', readonly=False)
        mem2 = IndirectMemory2D.create_memory(rows=1, cols=2, format='b', readonly=False)
        mem.copy_to(mem2, cast=True)
        self.assertTrue(True)

    def test_diff_itemsize_with_cast_to(self):
        mem  = IndirectMemory2D.create_memory(rows=1, cols=2, format='B', readonly=False)
        mem2 = IndirectMemory2D.create_memory(rows=1, cols=2, format='i', readonly=False)
        with self.assertRaises(BufferError) as context:
            mem.copy_to(mem2, cast=True)
        self.assertEqual("different itemsizes", context.exception.args[0])  


    def test_copy_to_indirect_memory(self):
        mem  = IndirectMemory2D.create_memory(rows=42, cols=21, format='i', readonly=False)
        mem2 = IndirectMemory2D.create_memory(rows=42, cols=21, format='i', readonly=False)
        memoryview(mem2)[15,2] = 42
        mem2.copy_to(mem)
        self.assertEqual(memoryview(mem)[15,2], 42)

##  view_from rows:
    def test_view_from_rows_refcount(self):
        import numpy as np
        a = np.zeros((3,4), order="C")
        cnt = sys.getrefcount(a)
        mem  = IndirectMemory2D.view_from_rows(a)
        self.assertEqual(cnt+1, sys.getrefcount(a))
        del mem
        self.assertEqual(cnt, sys.getrefcount(a))


    def test_view_from_rows_bufferlocked(self):
        import numpy as np
        a = np.zeros((3,4), order="C")
        mem  = IndirectMemory2D.view_from_rows(a)
        with self.assertRaises(ValueError) as context:
            a.resize((55,1))
        self.assertTrue("cannot resize" in context.exception.args[0])
        del mem
        a.resize((55,1))
        self.assertEqual(a.shape[0], 55)


    def test_view_from_rows_wrong_mem_layout(self):
        import numpy as np
        a = np.zeros((3,4), order="F")
        with self.assertRaises(BufferError) as context:
            mem  = IndirectMemory2D.view_from_rows(a)
        self.assertEqual("rows of the buffer-object aren't contiguous", context.exception.args[0])

    def test_view_from_rows_too_many_dims(self):
        import numpy as np
        a = np.zeros((3,4,3), order="C")
        with self.assertRaises(BufferError) as context:
            mem  = IndirectMemory2D.view_from_rows(a)
        self.assertEqual("expected at most 2 but found 3 dimensions", context.exception.args[0])


    def test_view_from_one_row_1d(self):
        a = array.array("i", [1,2,3,4])
        mem  = IndirectMemory2D.view_from_rows(a)
        self.assertEqual(mem.shape[0], 1)
        self.assertEqual(mem.shape[1], 4)
        self.assertEqual(memoryview(mem)[0,2], 3)
        memoryview(mem)[0,2] = 42
        self.assertEqual(a[2], 42)


    def test_view_from_one_row_2d(self):
        import numpy as np
        a = np.array([[1,2,3,4]], order="C")
        mem  = IndirectMemory2D.view_from_rows(a)
        self.assertEqual(mem.shape[0], 1)
        self.assertEqual(mem.shape[1], 4)
        self.assertEqual(memoryview(mem)[0,2], 3)
        memoryview(mem)[0,2] = 42
        self.assertEqual(a[0,2], 42)


    def test_view_from_rows(self):
        import numpy as np
        a =  np.zeros((7,4), order="C")
        a[1,2] = 21
        a[2,1] = 42
        mem  = IndirectMemory2D.view_from_rows(a)
        self.assertEqual(mem.shape[0], 7)
        self.assertEqual(mem.shape[1], 4)
        self.assertEqual(memoryview(mem)[1,2], 21)
        self.assertEqual(memoryview(mem)[2,1], 42)
        memoryview(mem)[1,3] = 5
        memoryview(mem)[3,1] = 6
        self.assertEqual(a[1,3], 5)
        self.assertEqual(a[3,1], 6)


    def test_view_from_rows_from_view(self):
        import numpy as np
        a=np.arange(12).reshape((4,3))
        b=a[0::2,:]
        mem  = IndirectMemory2D.view_from_rows(b)
        self.assertEqual(mem.shape[0], 2)
        self.assertEqual(mem.shape[1], 3)
        self.assertEqual(memoryview(mem)[1,0], 6)
        memoryview(mem)[1,0] = 42
        self.assertEqual(a[2,0], 42)


    def test_view_from_rows_from_view_wrong_mem_layout(self):
        import numpy as np
        a=np.arange(24).reshape((4,6))
        b=a[0::2, 0::2]
        with self.assertRaises(BufferError) as context:
            mem  = IndirectMemory2D.view_from_rows(b)
        self.assertEqual("rows of the buffer-object aren't contiguous", context.exception.args[0])

##  view_from colums:
    def test_view_from_cols_refcount(self):
        import numpy as np
        a = np.zeros((3,4), order="F")
        cnt = sys.getrefcount(a)
        mem  = IndirectMemory2D.view_from_columns(a)
        self.assertEqual(cnt+1, sys.getrefcount(a))
        del mem
        self.assertEqual(cnt, sys.getrefcount(a))


    def test_view_from_cols_bufferlocked(self):
        import numpy as np
        a = np.zeros((3,4), order="F")
        mem  = IndirectMemory2D.view_from_columns(a)
        with self.assertRaises(ValueError) as context:
            a.resize((55,1))
        self.assertTrue("cannot resize" in context.exception.args[0])
        del mem
        a.resize((55,1))
        self.assertEqual(a.shape[0], 55)

    def test_view_from_cols_wrong_mem_layout(self):
        import numpy as np
        a = np.zeros((3,4), order="C")
        with self.assertRaises(BufferError) as context:
            mem  = IndirectMemory2D.view_from_columns(a)
        self.assertEqual("columns of the buffer-object aren't contiguous", context.exception.args[0])

    def test_view_from_cols_too_many_dims(self):
        import numpy as np
        a = np.zeros((3,4,3), order="F")
        with self.assertRaises(BufferError) as context:
            mem  = IndirectMemory2D.view_from_columns(a)
        self.assertEqual("expected at most 2 but found 3 dimensions", context.exception.args[0])


    def test_view_from_one_col_1d(self):
        a = array.array("i", [1,2,3,4])
        mem  = IndirectMemory2D.view_from_columns(a)
        self.assertEqual(mem.shape[0], 1)
        self.assertEqual(mem.shape[1], 4)
        self.assertEqual(memoryview(mem)[0,2], 3)
        memoryview(mem)[0,2] = 42
        self.assertEqual(a[2], 42)


    def test_view_from_one_col_2d(self):
        import numpy as np
        a = np.array([[1],[2],[3],[4]], order="F")
        mem  = IndirectMemory2D.view_from_columns(a)
        self.assertEqual(mem.shape[0], 1) #dimensions swapped
        self.assertEqual(mem.shape[1], 4) #dimensions swapped
        self.assertEqual(memoryview(mem)[0,2], 3) #dimensions swapped
        memoryview(mem)[0,2] = 42 #dimensions swapped
        self.assertEqual(a[2,0], 42)


    def test_view_from_cols(self):
        import numpy as np
        a =  np.zeros((4,7), order="F")
        a[1,2] = 21
        a[2,1] = 42
        mem  = IndirectMemory2D.view_from_columns(a)
        self.assertEqual(mem.shape[0], 7) #dimensions swapped
        self.assertEqual(mem.shape[1], 4) #dimensions swapped
        self.assertEqual(memoryview(mem)[1,2], 42) #dimensions swapped
        self.assertEqual(memoryview(mem)[2,1], 21) #dimensions swapped
        memoryview(mem)[1,3] = 5
        memoryview(mem)[3,1] = 6
        self.assertEqual(a[1,3], 6)  #dimensions swapped
        self.assertEqual(a[3,1], 5)  #dimensions swapped


    def test_view_from_cols_from_view(self):
        import numpy as np
        a=np.arange(12).reshape((3,4), order="F")
        b=a[:, 0::2]
        mem  = IndirectMemory2D.view_from_columns(b)
        self.assertEqual(mem.shape[0], 2) #dimensions swapped
        self.assertEqual(mem.shape[1], 3) #dimensions swapped
        self.assertEqual(memoryview(mem)[1,0], 6) #dimensions swapped
        memoryview(mem)[1,0] = 42         #dimensions swapped
        self.assertEqual(a[0,2], 42)


    def test_view_from_rows_from_view_wrong_mem_layout(self):
        import numpy as np
        a=np.arange(24).reshape((4,6))
        b=a[0::2, 0::2]
        with self.assertRaises(BufferError) as context:
            mem  = IndirectMemory2D.view_from_columns(b)
        self.assertEqual("columns of the buffer-object aren't contiguous", context.exception.args[0])


