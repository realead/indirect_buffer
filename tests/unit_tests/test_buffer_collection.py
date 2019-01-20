# the actual test is in the cython module
import sys
import unittest
import pyximport; pyximport.install(language_level=sys.version_info[0])
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

