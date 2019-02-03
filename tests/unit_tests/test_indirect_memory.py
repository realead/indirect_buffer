# the actual test is in the cython module
import sys
import unittest
import pyximport; pyximport.install(language_level=sys.version_info[0])
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




