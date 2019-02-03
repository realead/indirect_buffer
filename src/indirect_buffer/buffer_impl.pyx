 
from cpython cimport buffer, PyBuffer_Release
from libc.stdlib cimport calloc,free

import struct


cdef char *empty_buf=""

# info about buffer, valid as long as exporter is alive
cdef struct BufferInfo:
    char *format
    Py_ssize_t len
    void *ptr

cdef BufferInfo get_info_via_buffer(obj):
    cdef BufferInfo info
    cdef buffer.Py_buffer view
    buffer.PyObject_GetBuffer(obj, &view, buffer.PyBUF_FORMAT|buffer.PyBUF_ANY_CONTIGUOUS)
    info.format = view.format
    info.ptr    = view.buf
    info.len    = view.len//view.itemsize
    buffer.PyBuffer_Release(&view)
    return info



cdef ensure_bytes(obj):
    if not isinstance(obj, bytes):
        obj=obj.encode('ascii')
    return obj

#
# helper classes for managing the memory ownership
#
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


cdef class OnlyPointerNanny:
    """
       frees only the ptr, but not ptr[i]
    """
    cdef void *ptr
    cdef Py_ssize_t row_count  #just for info, not really used

    @staticmethod
    cdef OnlyPointerNanny create(void *ptr, row_count):
         cdef OnlyPointerNanny self = OnlyPointerNanny()
         self.ptr = ptr
         self.row_count = row_count
         return self

    def __dealloc__(self):      
        free(self.ptr)
        self.ptr=NULL  


#
# The working horse: exposes data via BufferInterface
#  

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
        self.memory_nanny = None
        #need to set only once (could be a global variable as well)     
        self.suboffsets[0] = 0
        self.suboffsets[1] = -1

                
    cdef int**  as_int_ptr_ptr(self):
        return <int**>self.ptr

  
    cdef void __set_dimensions(self, Py_ssize_t rows, Py_ssize_t cols):
        self.row_count = rows
        self.shape[0] = rows
        self.column_count = cols
        self.shape[1] = cols


    cdef void __set_format(self, object format):
        self.format = ensure_bytes(format)
        self.element_size = struct.calcsize(self.format) 
        self.strides[0] = sizeof(void *)
        self.strides[1] = self.element_size


    def get_format(self):
        return self.format


    def reinterpret_data(self, new_format):
        cdef bytes new_format_b = ensure_bytes(new_format)
        if new_format_b == self.format:
            return

        if self.buffer_lock_cnt != 0:
            raise BufferError('buffer is locked')

        cdef Py_ssize_t row_len = self.column_count * self.element_size        
        cdef Py_ssize_t new_element_size = struct.calcsize(new_format_b)

        cdef Py_ssize_t new_column_count = row_len//new_element_size
        self.__set_dimensions(self.row_count, new_column_count)
        self.__set_format(new_format_b)


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
    def create_memory(Py_ssize_t rows, Py_ssize_t cols, object format, readonly=False):
        return IndirectMemory2D.create(rows, cols, format, readonly)

    @staticmethod
    cdef IndirectMemory2D create(Py_ssize_t rows, Py_ssize_t cols, object format, int readonly):
        """
        """
        cdef IndirectMemory2D mem = IndirectMemory2D()
        mem.own_data = 2
        mem.readonly = readonly
        mem.__set_dimensions(rows, cols)
        mem.__set_format(format)
        mem.ptr = calloc(rows, sizeof(void*))
        if NULL == mem.ptr:
            raise MemoryError("Error in first allocation")
        mem.memory_nanny = WholeMemoryNanny.create(mem.ptr, rows)
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
        return IndirectMemory2D.from_ptr_with_memory_nanny(ptr,rows, cols, format, readonly, None)


    @staticmethod
    cdef IndirectMemory2D from_ptr_with_memory_nanny(void* ptr, Py_ssize_t rows, Py_ssize_t cols, object format, int readonly, object memory_nanny):
        """
        """
        cdef IndirectMemory2D mem = IndirectMemory2D()
        mem.own_data = 0
        mem.readonly = readonly
        mem.__set_dimensions(rows, cols)
        mem.__set_format(format)
        mem.ptr = ptr
        mem.memory_nanny =  memory_nanny
        return mem


    @staticmethod
    def from_ctype_ptr(ptr, Py_ssize_t rows, Py_ssize_t cols, int readonly=False, object memory_nanny=None):
        """
        wraps indirect ctypes pointers (e.g double**), 
        if memory_nanny == None, keeps a reference to the ctypes-objects 
                          and assumes, that the pointer lives at least as long as the ctypes-object
        """
        cdef BufferInfo info = get_info_via_buffer(ptr)
        if    info.format == NULL       or  \
              info.format[0] == 0       or  \
              info.format[0] != ord('&') or \
              info.format[1] == 0       or  \
              info.format[1] == ord('&'):
            raise BufferError("wrong format: "+str(bytes(info.format)))
        cdef char *format_view = info.format+1
        if memory_nanny is None:
            memory_nanny = ptr
        if info.len < rows:
            raise BufferError("less rows than expected: {0} vs. {1}".format(info.len, rows))
        return IndirectMemory2D.from_ptr_with_memory_nanny(info.ptr, rows, cols, info.format[1:], readonly, None)




#
#
# Extension of the BufferInterface
#
#


# small helper class for managing of views

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

    cdef int get_readonly(self):
        return self.view.readonly

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
        cdef int my_readonly = 0

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

            if view.get_readonly()>0:
                my_readonly = 1

            # view is OK:
            self.views.append(view)

        #initialize IndirectMemory2D:
        self.own_data = 1  # it owns only the direct ptr
        self.readonly = my_readonly
        self.__set_dimensions(len(self.views), my_column_count)
        self.__set_format(my_format)
        self.ptr = calloc(self.row_count, sizeof(void*))
        if NULL == self.ptr:
            raise MemoryError("Error in first allocation")
        self.memory_nanny = OnlyPointerNanny.create(self.ptr, self.row_count)
        cdef void** ptr = <void**> self.ptr
        for i,view in enumerate(self.views):
             ptr[i] = view.get_ptr()



    def make_read_only(self):
        # all consumers should  see the same readonly flag!
        if self.readonly == 0 and self.buffer_lock_cnt != 0:
            raise BufferError('buffer is locked')
        self.readonly = 1
        
    
