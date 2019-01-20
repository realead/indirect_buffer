 
from cpython cimport buffer, PyBuffer_Release
from libc.stdlib cimport calloc,free

import struct


cdef char *empty_buf=""


cdef ensure_bytes(obj):
    if not isinstance(obj, bytes):
        obj=obj.encode('ascii')
    return obj

cdef class IndirectMemory2D:
    """
    helper class, owner/manager of the memory
    """
   
    def __cinit__(self):
        self.ptr = NULL
        self.own_data = 0  # 0  means no, 1 means only ptr, 2 means whole data (also subpointers)
        self.row_count = 0
        self.column_count = 0
        self.element_size = 0
        self.buffer_lock_cnt = 0
        self.readonly = 0
        self.format = None 
        #need to set only once (could be a global variable as well)     
        self.suboffsets[0] = 0
        self.suboffsets[1] = -1

    def __dealloc__(self):
        cdef Py_ssize_t i
        cdef void** p
        if  self.own_data>0 and self.ptr is not NULL:
            p = <void**> self.ptr
            if self.own_data>1:
                for i in range(self.row_count):
                    if p[i] is not NULL:
                        free(p[i])
            free(self.ptr)
            self.ptr=NULL;
                
    cdef int**  as_int_ptr_ptr(self):
        return <int**>self.ptr

  
    cdef void _set_dimensions(self, Py_ssize_t rows, Py_ssize_t cols):
        self.row_count = rows
        self.shape[0] = rows
        self.column_count = cols
        self.shape[1] = cols

    cdef void _set_format(self, object format):
        self.format = ensure_bytes(format)
        self.element_size = struct.calcsize(self.format) 
        self.strides[0] = sizeof(void *)
        self.strides[1] = self.element_size

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

         
        # 0 or 1 possible as long as the same for all
        if (flags & buffer.PyBUF_WRITABLE) == buffer.PyBUF_WRITABLE and self.readonly == 1:
            raise BufferError("buffer is not writable")
        view.readonly = self.readonly

        # should be original value, even if buffer.format is set to NULL
        view.itemsize = self.element_size;

        # format:
        if (flags & buffer.PyBUF_FORMAT) == buffer.PyBUF_FORMAT:
             view.format = self.format
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
    cdef IndirectMemory2D create(Py_ssize_t rows, Py_ssize_t cols, object format, int readonly):
        """
        """
        cdef IndirectMemory2D mem = IndirectMemory2D()
        mem.own_data = 2
        mem.readonly = readonly
        mem._set_dimensions(rows, cols)
        mem._set_format(format)
        mem.ptr = calloc(rows, sizeof(void*))
        if NULL == mem.ptr:
            raise MemoryError("Error in first allocation")
        cdef Py_ssize_t i
        cdef void** ptr = <void**> mem.ptr
        for i in range(rows):
             ptr[i] = calloc(cols, mem.element_size)
             if ptr[i] is NULL:
                raise MemoryError("Allocation of row "+str(i))  # allocated memory will be freed as soon as mem is deallocated
        return mem

    @staticmethod
    cdef IndirectMemory2D from_ptr(void* ptr, Py_ssize_t rows, Py_ssize_t cols, object format, int readonly):
        """
        """
        cdef IndirectMemory2D mem = IndirectMemory2D()
        mem.own_data = 0
        mem.readonly = readonly
        mem._set_dimensions(rows, cols)
        mem._set_format(format)
        mem.ptr = ptr
        return mem


#as a simple contiguous memory
cdef class BufferHolder: 
    cdef buffer.Py_buffer view
    cdef bint buffer_set
    def __cinit__(self, obj):
        buffer.PyObject_GetBuffer(obj, &(self.view), buffer.PyBUF_FORMAT|buffer.PyBUF_ANY_CONTIGUOUS)
        buffer_set = 1

    def __dealloc__(self):
        if self.buffer_set:
            PyBuffer_Release(&(self.view)) 

    cdef Py_ssize_t get_len(self):
        return self.view.len//self.view.itemsize

    cdef bytes get_format(self):
        return self.view.format  
    
    cdef int get_ndim(self):
        return self.view.ndim 

    cdef void* get_ptr(self):
        return self.view.buf




cdef class BufferCollection2D(IndirectMemory2D):  
    # cdef list views 

    def __cinit__(self, rows, column_count=-1, format=None, unravel = True):
        """
           column_count = -1 for auto detecting the number of columns
           format = None for auto detecting the format
           for unravel=False only one dimensional arrays are accepted, otherwise continuous memory is interpreted as unraveled
        """
        self.views = []
        cdef Py_ssize_t my_column_count = column_count
        cdef bytes my_format = None if format is None else ensure_bytes(format)

        cdef BufferHolder view
        for i, obj in enumerate(rows):
            view = BufferHolder(obj)

            if not unravel and view.get_ndim()!=1:
                raise BufferError("{0}. object has dimensionality: {1}, but only one-dimensional objects are accepted".format(i,view.get_ndim()))
            
            if my_format is None:
                my_format = view.get_format()
            elif my_format != view.get_format():
                raise BufferError("{0}. object, expected format: [{1}], found format: [{2}]".format(i, my_format, view.get_format()))

            if my_column_count == -1:
                my_column_count = view.get_len()
            elif my_column_count != view.get_len():
                raise BufferError("{0}. object, expected column count: {1}, found column count: {2}".format(i, my_column_count, view.get_len()))

            # view is OK:
            self.views.append(view)

        #initialize IndirectMemory2D:
        self.own_data = 1  # it owns only the direct ptr
        self._set_dimensions(len(self.views), my_column_count)
        self._set_format(my_format)
        self.ptr = calloc(self.row_count, sizeof(void*))
        if NULL == self.ptr:
            raise MemoryError("Error in first allocation")
        cdef void** ptr = <void**> self.ptr
        for i,view in enumerate(self.views):
             ptr[i] = view.get_ptr()


        
    
