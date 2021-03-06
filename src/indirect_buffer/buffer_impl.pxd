 

cdef class IndirectMemory2D:

    cdef void*       ptr
    cdef Py_ssize_t  row_count
    cdef Py_ssize_t  column_count
    cdef Py_ssize_t  element_size
    cdef Py_ssize_t  shape[2]
    cdef Py_ssize_t  strides[2]
    cdef Py_ssize_t  suboffsets[2]
    cdef Py_ssize_t  buffer_lock_cnt
    cdef bint        readonly
    cdef bytes       format
    cdef object      memory_nanny
   
                
    cdef int**  as_int_ptr_ptr(self)

    @staticmethod
    cdef IndirectMemory2D create(Py_ssize_t rows, Py_ssize_t cols, object format, int readonly)

    @staticmethod
    cdef IndirectMemory2D from_ptr(void* ptr, Py_ssize_t rows, Py_ssize_t cols, object format, int readonly)
    @staticmethod
    cdef IndirectMemory2D from_ptr_with_memory_nanny(void* ptr, Py_ssize_t rows, Py_ssize_t cols, object format, int readonly, object memory_nanny)

    @staticmethod
    cdef IndirectMemory2D cy_view_from_rows(object array2d, bint readonly=*)
    @staticmethod
    cdef IndirectMemory2D cy_view_from_columns(object array2d, bint readonly=*)

    # private:
    cdef void __set_dimensions(self, Py_ssize_t rows, Py_ssize_t cols)
    cdef void __set_format(self, object format)

 
# collects different buffers,every buffer means a row.
# all buffers should be continous, one-dimensional and have the same length.
cdef class BufferCollection2D(IndirectMemory2D):  
    cdef list views
