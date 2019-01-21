 

cdef class IndirectMemory2D:

    cdef void*       ptr
    cdef bint        own_data
    cdef Py_ssize_t  row_count
    cdef Py_ssize_t  column_count
    cdef Py_ssize_t  element_size
    cdef Py_ssize_t  shape[2]
    cdef Py_ssize_t  strides[2]
    cdef Py_ssize_t  suboffsets[2]
    cdef Py_ssize_t  buffer_lock_cnt
    cdef int         readonly
    cdef bytes       format
    cdef object      memory_nanny
   
                
    cdef int**  as_int_ptr_ptr(self)

    @staticmethod
    cdef IndirectMemory2D create(Py_ssize_t rows, Py_ssize_t cols, object format, int readonly)

    @staticmethod
    cdef IndirectMemory2D from_ptr(void* ptr, Py_ssize_t rows, Py_ssize_t cols, object format, int readonly)

    # private:
    cdef void _set_dimensions(self, Py_ssize_t rows, Py_ssize_t cols)
    cdef void _set_format(self, object format)

 
# collects different buffers,every buffer means a row.
# all buffers should be continous, one-dimensional and have the same length.
cdef class BufferCollection2D(IndirectMemory2D):  
    cdef list views
