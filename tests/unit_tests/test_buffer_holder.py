import sys
import unittest

import ctypes

from indirect_buffer.buffer_impl import BufferHolder

class TestBufferHolder(unittest.TestCase):

    def test_live_cycle(self):
         data = (ctypes.c_double*2)(1.0,2.0)
         ref_cnt = sys.getrefcount(data)
         holder = BufferHolder(data)
         self.assertTrue(holder.buffer_is_set())
         self.assertEqual(ref_cnt+1, sys.getrefcount(data))
         del holder
         self.assertEqual(ref_cnt, sys.getrefcount(data))

