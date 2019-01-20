import unittest


from cython cimport view
from indirect_buffer.buffer_impl cimport BufferCollection2D


class BufferCollection2DTester(unittest.TestCase): 
    def test_create(self):
        arr1=bytearray(b'aa')
        arr2=bytearray(b'bb')
        mem = BufferCollection2D([arr1, arr2])
        cdef char[::view.indirect_contiguous, ::1] data = mem
        self.assertEqual(data[0][0], ord('a'))
        data[1][1]=ord('c')
        self.assertEqual(arr2[1], ord('c'))


    def test_create_unravel(self):
        arr1=view.array(shape=(2, 2), itemsize=sizeof(int), format="i")
        arr2=view.array(shape=(4,1), itemsize=sizeof(int), format="i")
        mem = BufferCollection2D([arr1, arr2], unravel=True)
        self.assertTrue(True)


    def test_create_no_unravel_ok(self):
        arr=view.array(shape=(4,), itemsize=sizeof(int), format="i")
        mem = BufferCollection2D([arr], unravel=False)
        self.assertTrue(True)


    def test_create_no_unravel_error(self):
        arr=view.array(shape=(2, 2), itemsize=sizeof(int), format="i")
        with self.assertRaises(BufferError) as context:
            mem = BufferCollection2D([arr], unravel=False)
        self.assertEqual("0. object has dimensionality: 2, but only one-dimensional objects are accepted", context.exception.args[0])


    def test_create_no_unravel_error2(self):
        arr=view.array(shape=(4, 1, 1), itemsize=sizeof(int), format="i")
        with self.assertRaises(BufferError) as context:
            mem = BufferCollection2D([arr], unravel=False)
        self.assertEqual("0. object has dimensionality: 3, but only one-dimensional objects are accepted", context.exception.args[0])


