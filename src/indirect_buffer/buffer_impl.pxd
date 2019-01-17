 

cdef class IndirectMemory2D:

    cdef void*       ptr
    cdef bint        own_data
    cdef Py_ssize_t  row_count
    cdef Py_ssize_t  column_count
    cdef Py_ssize_t  element_size
   
                
    cdef int**  as_int_ptr_ptr(self)

    @staticmethod
    cdef IndirectMemory2D create(Py_ssize_t rows, Py_ssize_t cols, Py_ssize_t element_size)

    @staticmethod
    cdef IndirectMemory2D from_ptr(void* ptr, Py_ssize_t rows, Py_ssize_t cols, Py_ssize_t element_size)

    
