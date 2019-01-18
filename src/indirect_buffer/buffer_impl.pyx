 
from cpython cimport buffer
from libc.stdlib cimport calloc,free


cdef char *empty_buf=""


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
        self.buffer_lock_cnt = 0

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

  


    def __getbuffer__(self, buffer.Py_buffer *view, int flags):
        #is input sane?
        if(view==NULL):
            raise BufferError("view==NULL argument is obsolete")


        #should never happen, just to be sure
        if NULL == self.ptr:
            view.buf = empty_buf
        else:
            view.buf = self.ptr

        view.obj = self; # increments ref count
       
        
        # the length that the logical structure would have if 
        # it were copied to a contiguous representation
        # in bytes
        view.len = self.row_count * self.column_count * self.element_size

        # for the time being everybody can write 
        # (alowed no matter whether  PyBUF_WRITABLE is in flags)
        view.readonly = 0;

        # should be original value, even if buffer.format is set to NULL
        view.itemsize = self.element_size;

        # format:
        if (flags & buffer.PyBUF_FORMAT) == buffer.PyBUF_FORMAT:
             #TODO: right format
             view.format = "B"
        else:
             view.format = NULL

        # obviously there are 2 dimensions:
        view.ndim = 2;
        
        # view.shape==NULL only for PyBUF_SIMPLE
        # view.strides==NULL only for PyBUF_ND (which includes PyBUF_SIMPLE)
        # view.suboffsets==NULL only for PyBUF_STRIDES (which includes PyBUF_ND)
        #
        # however our memory layout doesn't make any sense without view.suboffsets
        # so throw if it is not PyBUF_INDIRECT 
        if (flags & buffer.PyBUF_INDIRECT) != buffer.PyBUF_INDIRECT:
               raise BufferError("need PyBUF_INDIRECT-able buffer-consumer")

        view.shape = self.shape
        view.strides = self.strides
        view.suboffsets = self.suboffsets

        # no need for internal data
        view.internal = NULL

        self.buffer_lock_cnt+=1


    def __releasebuffer__(self, buffer.Py_buffer *view):
        self.buffer_lock_cnt-=1

    @staticmethod
    cdef IndirectMemory2D create(Py_ssize_t rows, Py_ssize_t cols, Py_ssize_t element_size):
        """
        """
        cdef IndirectMemory2D mem = IndirectMemory2D()
        mem.own_data = 1
        mem.row_count = rows
        mem.shape[0] = rows
        mem.column_count = cols
        mem.shape[1] = cols
        mem.element_size = element_size
        mem.strides[0] = sizeof(void *)
        mem.strides[1] = element_size
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
        mem.shape[0] = rows
        mem.column_count = cols
        mem.shape[1] = cols
        mem.element_size = element_size
        mem.strides[0] = sizeof(void *)
        mem.strides[1] = element_size
        mem.ptr = ptr
        return mem

    
