# the actual test is in the cython module
import sys
import unittest
import pyximport; pyximport.install(language_level=sys.version_info[0], build_dir="temp_builds")
from cytest_buffer_collection import *

import array

from indirect_buffer.buffer_impl import BufferCollection2D

class BufferCollection2DPurePython(unittest.TestCase):
    def test_create_diff_sizes(self):
        arr1=bytearray(b'aa')
        arr2=bytearray(b'bbc')
        with self.assertRaises(BufferError) as context:
            mem = BufferCollection2D([arr1, arr2])
        self.assertEqual('1. object, expected column count: 2, found column count: 3', context.exception.args[0])


    def test_create_wrong_size(self):
        arr1=bytearray(b'aa')
        arr2=bytearray(b'bbc')
        with self.assertRaises(BufferError) as context:
            mem = BufferCollection2D([arr1, arr2], column_count=3)
        self.assertEqual('0. object, expected column count: 3, found column count: 2', context.exception.args[0])


    def test_create_right_size(self):
        arr1=bytearray(b'aa')
        arr2=bytearray(b'bb')
        mem = BufferCollection2D([arr1, arr2], column_count=2)
        self.assertTrue(True)


    def test_create_diff_types(self):
        arr1=bytearray(b'aa')
        arr2=array.array('i',[1,2])
        with self.assertRaises(BufferError) as context:
            mem = BufferCollection2D([arr1, arr2])
        self.assertEqual("1. object, expected format: [b'B'], found format: [b'i']", context.exception.args[0])


    def test_create_wrong_type(self):
        arr1=bytearray(b'aa')
        with self.assertRaises(BufferError) as context:
            mem = BufferCollection2D([arr1], format='i')
        self.assertEqual("0. object, expected format: [b'i'], found format: [b'B']", context.exception.args[0])


    def test_create_right_type(self):
        arr1=bytearray(b'aa')
        mem = BufferCollection2D([arr1], format='B')
        self.assertTrue(True)

   
    def test_readonly_auto_yes(self):
        arr1=bytearray(b'aa')
        arr2=b'aa'
        mem = BufferCollection2D([arr1, arr2])
        view = memoryview(mem)
        self.assertEqual(view.readonly, 1)


    def test_readonly_auto_no(self):
        arr1=bytearray(b'aa')
        mem = BufferCollection2D([arr1])
        view = memoryview(mem)
        self.assertEqual(view.readonly, 0)


    def test_readonly_make_read_only(self):
        arr1=bytearray(b'aa')
        mem = BufferCollection2D([arr1])
        mem.make_read_only()
        view = memoryview(mem)
        self.assertEqual(view.readonly, 1)


    def test_readonly_make_read_only_locked(self):
        arr1=bytearray(b'aa')
        mem = BufferCollection2D([arr1])
        view = memoryview(mem)
        self.assertEqual(view.readonly, 0)
        with self.assertRaises(BufferError) as context:
            mem.make_read_only()
        self.assertEqual("buffer is locked", context.exception.args[0])
        

    def test_readonly_make_read_only_if_readonly(self):
        arr1 = b'aa'
        mem = BufferCollection2D([arr1])
        view = memoryview(mem)
        self.assertEqual(view.readonly, 1)
        mem.make_read_only()
        self.assertTrue(True)


    def test_buffer_locked_unlocked(self):
        arr1=array.array('i',[2,3])
        arr2=array.array('i',[2,3])
        lst = [arr1, arr2]
        mem = BufferCollection2D(lst)
        for arr in lst:
            with self.assertRaises(BufferError) as context:
                 arr.pop()
            self.assertEqual('cannot resize an array that is exporting buffers', context.exception.args[0])
        del mem # unlock
        for arr in lst:
            self.assertEqual(arr.pop(), 3)


    def test_arrays_referenced_unreferenced(self):
        arr1=array.array('i',[2,3])
        arr2=array.array('i',[2,3])
        lst = [arr1, arr2]
        cnts = [sys.getrefcount(x) for x in lst]
        mem = BufferCollection2D(lst)
        cnts_after = [sys.getrefcount(x)-1 for x in lst]
        self.assertEqual(cnts, cnts_after)

        del mem # unference
   
        cnts_after = [sys.getrefcount(x) for x in lst]
        self.assertEqual(cnts, cnts_after)



