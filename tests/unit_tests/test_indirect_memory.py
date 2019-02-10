# the actual test is in the cython module
import sys
import unittest
import pyximport; pyximport.install(language_level=sys.version_info[0], build_dir="temp_builds")
from cytest_indirect_memory import *

import ctypes

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

 
