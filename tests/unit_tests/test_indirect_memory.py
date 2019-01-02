# the actual test is in the cython module
import sys
import unittest
import pyximport; pyximport.install(language_level=sys.version_info[0])
from cytest_indirect_memory import *

