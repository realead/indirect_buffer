 
from libc.stdlib cimport calloc,free

cdef class IndirectMemory2D:
    """
    helper class, owner/manager of the memory
    """
    #cdef void*       ptr
    #cdef bint        own_data
    #cdef Py_ssize_t  row_count
    #cdef Py_ssize_t  column_count
    #cdef Py_ssize_t  element_size
   
    def __cinit__(self):
        self.ptr = NULL
        self.own_data = 0
        self.row_count = 0
        self.column_count = 0
        self.element_size = 0

    def __dealloc__(self):
        cdef Py_ssize_t i
        cdef void** p
        if  self.own_data and self.ptr is not NULL:
            p = <void**> self.ptr
            for i in range(self.row_count):
                if p[i] is not NULL:
                    free(p[i])
            free(self.ptr)
            self.ptr=NULL;
                
    cdef int**  as_int_ptr_ptr(self):
        return <int**>self.ptr

    @staticmethod
    cdef IndirectMemory2D create(Py_ssize_t rows, Py_ssize_t cols, Py_ssize_t element_size):
        """
        """
        cdef IndirectMemory2D mem = IndirectMemory2D()
        mem.own_data = 1
        mem.row_count = rows
        mem.column_count = cols
        mem.element_size = element_size
        mem.ptr = calloc(rows, sizeof(void*))
        if NULL == mem.ptr:
            raise MemoryError("Error in first allocation")
        cdef Py_ssize_t i
        cdef void** ptr = <void**> mem.ptr
        for i in range(rows):
             ptr[i] = calloc(cols, element_size)
             if ptr[i] is NULL:
                raise MemoryError("Allocation of row "+str(i))  # allocated memory will be freed as soon as mem is deallocated
        return mem

    @staticmethod
    cdef IndirectMemory2D from_ptr(void* ptr, Py_ssize_t rows, Py_ssize_t cols, Py_ssize_t element_size):
        """
        """
        cdef IndirectMemory2D mem = IndirectMemory2D()
        mem.own_data = 0
        mem.row_count = rows
        mem.column_count = cols
        mem.element_size = element_size
        mem.ptr = ptr
        return mem

    
