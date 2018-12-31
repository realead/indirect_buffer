import sys
from setuptools import setup, find_packages, Extension
from Cython.Build import cythonize


#for the time being only with cython:
USE_CYTHON = True



extensions = Extension(
            name='indirect_buffer.buffer_impl',
            sources = ["indirect_buffer/buffer_impl.pyx"]
    )

if USE_CYTHON:
    extensions = cythonize(extensions, compiler_directives={'language_level' : sys.version_info[0]})

kwargs = {
      'name':'indirect_buffer',
      'version':'0.1.0',
      'description':'a buffer for indirect memory layouts',
      'author':'Egor Dranischnikow',
      'url':'https://github.com/realead/indirect_buffer',
      'packages':find_packages(),
      'license': 'MIT',
      'ext_modules':  extensions,

       #ensure pxd-files:
      'package_data' : { 'indirect_buffer': ['*.pxd','*.pxi']},
      'include_package_data' : True,
      'zip_safe' : False  #needed because setuptools are used
}



setup(**kwargs)
