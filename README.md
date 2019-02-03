# indirect_buffer

implements buffer protocol for indirect memory layouts

## About:

   Wraps indirect 2D memory layouts, e.g. `int**` in Python via buffer-protocol. Makes it possible to pass data from/to Python to/from C/C++-routines with such layout.

   This is Python3-only package.


## Dependencies:

Essentials: 

  - Python 3 (tested with Python 3.6)
  - setuptools
  - Cython
  - c-build chain

Additional dependencies for tests:
   
  - `sh`
  - `virtualenv`


## Instalation:

To install the module using pip run:

    pip install https://github.com/realead/indirect_buffer/zipball/master

It is possible to uninstall it afterwards via

    pip indirect_buffer cykhash

You can also install using the setup.py file from the root directory of the project:

    python setup.py install

However, there is no easy way to deinstall it afterwards (only manually) if setup.py was used directly.


## Usage

### IndirectMemory2D

To create memory with indirect layout, in the example below a writeable 2x3-`int**`, use:


    from indirect_buffer import IndirectMemory2D
    mem = IndirectMemory2D.create_memory(rows=2, cols=3, format='i', readonly=False)


`format` should be given as usual (for example in `struct`-module).

Use `memoryview` to access the data:

    view1 = memoryview(mem)
    view2 = memoryview(mem)
    view1[1,2] =  42
    print(view2[1,2], 42)

Use 

    @staticmethod
    cdef IndirectMemory2D create(Py_ssize_t rows, Py_ssize_t cols, object format, int readonly)

i.e.:

    from indirect_buffer.buffer_impl cimport IndirectMemory2D
    mem = IndirectMemory2D.create(5,6,b'i',0)

In Cython code, it is also possible to create a `IndirectMemory2D` from already existing pointer, which for example is returned by a call to C-API:

    @staticmethod
    cdef IndirectMemory2D from_ptr(void* ptr, Py_ssize_t rows, Py_ssize_t cols, object format, int readonly)

i.e.:

    from indirect_buffer.buffer_impl cimport IndirectMemory2D
    cdef int val = 5
    cdef int *ptr = &val
    cdef int **ptr_ptr = &ptr
    mem = IndirectMemory2D.from_ptr(<void *>ptr_ptr,1,1,'i',0)

In this case `IndirectMemory2D` only wraps but doesn't own the memory. One could however pass a `memory_nanny`, which would make sure, that the pointer doesn't become dangling and is freed, when the `IndirectMemory2D` object is deallocated. Use for that:

    @staticmethod
    cdef IndirectMemory2D from_ptr_with_memory_nanny(void* ptr, Py_ssize_t rows, Py_ssize_t cols, object format, int readonly, object memory_nanny)

An example of such a `memory_nanny` could be the following `cdef`-class:

    from libc.stdlib cimport free
    cdef class WholeMemoryNanny:
        """
           frees not only the ptr, but also all ptr[i]
        """
        cdef void *ptr
        cdef Py_ssize_t row_count

        @staticmethod
        cdef WholeMemoryNanny create(void *ptr, Py_ssize_t row_count):
             cdef  WholeMemoryNanny self =  WholeMemoryNanny()
             self.ptr=ptr
             self.row_count=row_count
             return self

        def __dealloc__(self):
            cdef Py_ssize_t i
            cdef void** p
            if self.ptr is not NULL:
                p = <void**> self.ptr
                for i in range(self.row_count):
                        if p[i] is not NULL:
                            free(p[i])
                            p[i]=NULL
                free(self.ptr)
                self.ptr=NULL

The memory becomes deallocated as soon as the `memory_nanny`-object is deleted, which happens when `IndirectMemory2D` is deleted (unless `memory_nanny` is shared between multiple `IndirectMemory2D` objects.

#### with ctypes-pointers

One could also wrap an indirect pointer obtained by `ctypes` via

    @staticmethod
    def from_ctype_ptr(ptr, Py_ssize_t rows, Py_ssize_t cols, int readonly=False, object memory_nanny=None)

for example:

    import ctypes
    data=(ctypes.POINTER(ctypes.c_int)*2)((ctypes.c_int*1)(0), (ctypes.c_int*1)(42))

    mem = IndirectMemory2D.from_ctype_ptr(data, 2,1)

    mem.reinterpret_data('i') #  memoryview doesn't understand `<i`, but other consumers might do
    view=memoryview(mem)
    print(view[1,0])   # prints 42

Use `memory_nanny` to keep the object responsible for dealocation of underlying pointers alive. If `memory_nanny` is `None` then the reference to  the passed ctypes-object is used.

### BufferCollection2D

Can be used to view a collection of objects, which can export its continuous memory via protocol-buffer, as indirect memory. That means it can be used to pass a list of numpy-arrays as `double**` to C-API:

    from indirect_buffer import BufferCollection2D
    arr1=bytearray(b'ab')
    arr2=b'cd'
    mem = BufferCollection2D([arr1, arr2])
    view = memoryview(mem)
    print(view[1,1])  # 100 == ord("d")

The API:

    BufferCollection2D(rows, column_count=-1, format=None, unravel = True):

where:

  * `rows` the collection/iterable of buffer-objects. They all shoud have the same length and same format.
  * `column_count` number of columns/elements in an row. `-1` for auto-dection. Throws a `BufferError` if inconsistent.
  * `format` format-description. `None` for auto-dection. Throws a `BufferError` if inconsistent.
  * `unravel` pass `True` to unravel multi-dimensional arrays. In case of `False` only one-dimensional arrays are accepted.

The resulting `BufferCollection2D` is read-only, if ther is at least one read-only input object. One can also set the resulting buffer to read-only via `BufferCollection2D.make_read_only()`, which will throw if buffer is locked.s



## Testing:

For testing of the local version run:

    sh test_install.sh p3

in the `tests` subfolder.

For testing of the version from github run:

    sh test_install.sh p3 from-github

For keeping the the virtual enviroment after the tests:

    sh test_install.sh p3 local keep

## Versions:

  0.1.0: `IndirectMemory2D`, `BufferCollection2D`

