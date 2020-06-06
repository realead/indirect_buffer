 
from cpython cimport buffer, PyBuffer_Release
from libc.stdlib cimport calloc,free
from libc.string cimport memcpy, strcmp

import struct


cdef char *empty_buf=""

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



# small helper class for managing of views

cdef class BufferHolder: 
    cdef buffer.Py_buffer view
    cdef bint buffer_set
    def __cinit__(self, obj, buffer_flags = buffer.PyBUF_FORMAT|buffer.PyBUF_ANY_CONTIGUOUS):
        buffer.PyObject_GetBuffer(obj, &(self.view), buffer_flags)
        self.buffer_set = 1

    def __dealloc__(self):
        if self.buffer_set:
            PyBuffer_Release(&(self.view)) 

    cpdef bint buffer_is_set(self):
        return self.buffer_set

    cpdef Py_ssize_t get_len(self):
        return self.view.len//self.view.itemsize

    cpdef bytes get_format(self):
        if self.view.format == NULL:
            return b"B"
        return self.view.format  
    
    cpdef int get_ndim(self):
        return self.view.ndim 

    cdef void* get_ptr(self):
        return self.view.buf

    cpdef int get_readonly(self):
        return self.view.readonly


cdef void *get_item_pointer(Py_ssize_t row, Py_ssize_t col, void *buf, Py_ssize_t *strides, Py_ssize_t *suboffsets):
    cdef char *pointer = <char*>buf
    pointer += strides[0] * row
    if suboffsets!=NULL and suboffsets[0] >=0 : 
            pointer = (<char**>pointer)[0] + suboffsets[0];
    pointer += strides[1] * col
    return <void*>pointer;


cdef void  copy_checked_buffer(buffer.Py_buffer *src, buffer.Py_buffer *dest):
    cdef void *ptr_src = NULL
    cdef void *ptr_dest = NULL
    cdef Py_ssize_t row, col
    for row in range(src.shape[0]):
        for col in range(src.shape[1]):
            ptr_src = get_item_pointer(row, col, src.buf, src.strides, src.suboffsets)
            ptr_dest = get_item_pointer(row, col, dest.buf, dest.strides, dest.suboffsets)
            memcpy(ptr_dest, ptr_src, src.itemsize)


cdef void  copy_checked_buffer_rowwise(buffer.Py_buffer *src, buffer.Py_buffer *dest):
    cdef void *ptr_src = NULL
    cdef void *ptr_dest = NULL
    cdef Py_ssize_t row, col
    for row in range(src.shape[0]):
        ptr_src = get_item_pointer(row, 0, src.buf, src.strides, src.suboffsets)
        ptr_dest = get_item_pointer(row, 0, dest.buf, dest.strides, dest.suboffsets)
        memcpy(ptr_dest, ptr_src, src.itemsize*src.shape[1])



cdef int copy_buffer(buffer.Py_buffer *src, buffer.Py_buffer *dest, bint cast) except -1:
    #checks:
    if dest.readonly:
         raise BufferError("copying to readonly buffer")
    if dest.ndim != 2:
        raise BufferError("wrong number of dimensions: expected 2, received {0}".format(dest.ndim))
    if src.ndim != 2:
        raise BufferError("wrong number of dimensions: expected 2, received {0}".format(src.ndim))
    if src.shape == NULL or  dest.shape == NULL or src.shape[0]!=dest.shape[0] or src.shape[1]!=dest.shape[1]:
        raise BufferError("different shapes")
    if not cast and  strcmp(src.format, dest.format)!=0:
        raise  BufferError("different formats") 
    if cast and src.itemsize != dest.itemsize:   
        raise  BufferError("different itemsizes") 
    if src.strides == NULL or dest.strides == NULL:  
        raise  BufferError("invalid strides")   
    if src.suboffsets != NULL and src.suboffsets[1]>=0:  
        raise  BufferError("invalid suboffsets")   
    if dest.suboffsets != NULL and dest.suboffsets[1]>=0:  
        raise  BufferError("invalid suboffsets") 
    # now real copy:
    if src.strides[1] == src.itemsize and dest.strides[1] == dest.itemsize:
        # in this special (but probably common scenario) an optimization is possible
        copy_checked_buffer_rowwise(src, dest)
    else:
        copy_checked_buffer(src, dest)
    return 0


#
# The working horse: exposes data via BufferInterface
#  

cdef class IndirectMemory2D:
    """
    helper class, owner/manager of the memory
    """
   
    def __cinit__(self):
        self.ptr = NULL
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


    @property
    def shape(self):
        return self.shape

    
    def copy_from(self, obj, cast = False):
        """
            copies data from an object via buffer-protocol.
            obj should have the same shape and format (cast==False) or same itemsize (cast=True)
        """
        cdef BufferHolder src = BufferHolder(obj, buffer.PyBUF_FORMAT|buffer.PyBUF_INDIRECT)
        cdef BufferHolder dest = BufferHolder(self, buffer.PyBUF_FORMAT|buffer.PyBUF_INDIRECT)
        copy_buffer(&(src.view), &(dest.view), cast) 

    
    def copy_to(self, obj, cast = False):
        """
            copies data to an object via buffer-protocol.
            obj should have the same shape and format (cast==False) or same itemsize (cast=True)
        """
        cdef BufferHolder dest = BufferHolder(obj, buffer.PyBUF_FORMAT|buffer.PyBUF_INDIRECT)
        cdef BufferHolder src = BufferHolder(self, buffer.PyBUF_FORMAT|buffer.PyBUF_INDIRECT)
        copy_buffer(&(src.view), &(dest.view), cast) 


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
        mem.readonly = readonly
        mem.__set_dimensions(rows, cols)
        mem.__set_format(format)
        mem.ptr = ptr
        mem.memory_nanny =  memory_nanny
        return mem


    @staticmethod
    def from_ctype_ptr(ptr, Py_ssize_t rows, Py_ssize_t cols, bint readonly=False):
        """
        wraps indirect ctypes pointers (e.g double**), 
        if memory_nanny == None, keeps a reference to the ctypes-objects 
                          and assumes, that the pointer lives at least as long as the ctypes-object
        """
        cdef BufferHolder info = BufferHolder(ptr) 
        if    info.view.format == NULL       or  \
              info.view.format[0] == 0       or  \
              info.view.format[0] != ord('&') or \
              info.view.format[1] == 0       or  \
              info.view.format[1] == ord('&'):
            raise BufferError("wrong format: "+str(info.get_format()))
        if info.get_len() < rows:
            raise BufferError("less rows than expected: {0} vs. {1}".format(info.get_len(), rows))
        return IndirectMemory2D.from_ptr_with_memory_nanny(info.get_ptr(), rows, cols, info.view.format[1:], readonly, info)


    @staticmethod
    cdef IndirectMemory2D cy_view_from_rows(object array2d, bint readonly=False):
        """
        creates a view in indirect memory layout of an 2d-array in row-major-order
        """
        flags = buffer.PyBUF_FORMAT|buffer.PyBUF_STRIDES
        if not readonly:
           flags |= buffer.PyBUF_WRITABLE
        cdef BufferHolder info = BufferHolder(array2d, flags)
        #check buffer
        if info.get_ndim()>2:
           raise BufferError("expected at most 2 but found {0} dimensions".format(info.get_ndim()))
        if info.view.shape==NULL or info.view.strides==NULL:
           raise BufferError("requested information was not returned by buffer-object") 
        
        # get needed information
        cdef Py_ssize_t rows, cols, row_stride, col_stride
        if info.get_ndim()==1:
           rows = 1
           cols = info.view.shape[0]
           row_stride = 1 # actually whatever
           col_stride = info.view.strides[0]
        else:
           rows = info.view.shape[0]
           cols = info.view.shape[1]
           row_stride = info.view.strides[0]
           col_stride = info.view.strides[1]

        #check rows are contiguous:
        if col_stride!=info.view.itemsize:
            raise BufferError("rows of the buffer-object aren't contiguous")

        #create
        cdef OnlyPointerNanny nanny = OnlyPointerNanny()
        nanny.row_count = rows
        nanny.ptr = calloc(rows, sizeof(void*))
        if NULL == nanny.ptr:
            raise MemoryError("Error in first allocation")
        cdef Py_ssize_t i
        cdef void** ptr = <void**>nanny.ptr
        for i in range(rows):
            ptr[i] = <void*>((<char*>(info.view.buf))+i*row_stride)
        
        return IndirectMemory2D.from_ptr_with_memory_nanny(nanny.ptr, rows, cols, info.view.format, readonly, (info, nanny))

    @staticmethod
    def view_from_rows(array2d, bint readonly=False):
        return IndirectMemory2D.cy_view_from_rows(array2d, readonly)

    @staticmethod
    cdef IndirectMemory2D cy_view_from_columns(object array2d, bint readonly=False):
        """
        creates a view in indirect memory layout of an 2d-array in row-major-order
        """
        flags = buffer.PyBUF_FORMAT|buffer.PyBUF_STRIDES
        if not readonly:
           flags |= buffer.PyBUF_WRITABLE
        cdef BufferHolder info = BufferHolder(array2d, flags)
        #check buffer
        if info.get_ndim()>2:
           raise BufferError("expected at most 2 but found {0} dimensions".format(info.get_ndim()))
        if info.view.shape==NULL or info.view.strides==NULL:
           raise BufferError("requested information was not returned by buffer-object")

        # get needed information 
        cdef Py_ssize_t rows, cols, row_stride, col_stride
        if info.get_ndim()==1:
           rows = info.view.shape[0]
           cols = 1
           row_stride = info.view.strides[0]
           col_stride = 1 # actually whatever
        else:
           rows = info.view.shape[0]
           cols = info.view.shape[1]
           row_stride = info.view.strides[0]
           col_stride = info.view.strides[1]

        #check rows are contiguous:
        if row_stride!=info.view.itemsize:
            raise BufferError("columns of the buffer-object aren't contiguous")

        #create
        cdef OnlyPointerNanny nanny = OnlyPointerNanny()
        nanny.row_count = cols
        nanny.ptr = calloc(cols, sizeof(void*))
        if NULL == nanny.ptr:
            raise MemoryError("Error in first allocation")
        cdef Py_ssize_t i
        cdef void** ptr = <void**>nanny.ptr
        for i in range(cols):
            ptr[i] = <void*>((<char*>(info.view.buf))+i*col_stride)
        
        return IndirectMemory2D.from_ptr_with_memory_nanny(nanny.ptr, cols, rows, info.view.format, readonly, (info, nanny))

    @staticmethod
    def view_from_columns(array2d, bint readonly=False):
        return IndirectMemory2D.cy_view_from_columns(array2d, readonly)

#
#
# Extension of the BufferInterface
#
#



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
        
    
