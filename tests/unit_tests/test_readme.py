# the actual test is in the cython module
import sys
import unittest
import pyximport; pyximport.install(language_level=sys.version_info[0])
from cytest_readme import *


import ctypes
from indirect_buffer import BufferCollection2D, IndirectMemory2D



class ReadmePurePython(unittest.TestCase):

    def test_create_write_read_indirect_memory(self):
        mem = IndirectMemory2D.create_memory(rows=2, cols=3, format='i', readonly=False)
        view1 = memoryview(mem)
        view2 = memoryview(mem)
        view1[1,2] =  42
        self.assertEqual(view2[1,2], 42)


    def test_create_write_read_indirect_all(self):
        mem = IndirectMemory2D.create_memory(rows=22, cols=33, format='i', readonly=False)
        view1 = memoryview(mem)
        view2 = memoryview(mem)
        for row in range(22):
          for col in range(33):
              val = 33*row + col
              view1[row, col] = val
              self.assertEqual(view2[row, col], val)


    def test_create_write_read_only(self):
        mem = IndirectMemory2D.create_memory(rows=22, cols=33, format='i', readonly=True)
        view1 = memoryview(mem)
        with self.assertRaises(TypeError) as context:
            view1[0,0] = 1


    def test_access_BufferCollection2D(self):
        arr1=bytearray(b'ab')
        arr2=b'cd'
        mem = BufferCollection2D([arr1, arr2])
        view = memoryview(mem)
        self.assertEqual(view[1,1], ord("d"))


    def test_wrap_ctypes(self):
         data=(ctypes.POINTER(ctypes.c_int)*2)((ctypes.c_int*1)(0), (ctypes.c_int*1)(42))
         mem = IndirectMemory2D.from_ctype_ptr(data, 2,1)
         mem.reinterpret_data('i')
         view=memoryview(mem)
         self.assertEqual(view[1,0], 42)
         view[1,0] =  21
         self.assertEqual(data[1][0], 21)


