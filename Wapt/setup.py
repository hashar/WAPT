import setuptools
import os
import sys
import distutils.spawn
from setuptools import setup, Extension
from setuptools.command.build_ext import build_ext
from distutils.errors import *

__version__ = "0.8.25"

setup(name='waptcore',
      version=__version__,
      license="GPL v3",
      description='WAPT windows management core librairies',
      long_description="""
WAPT
""",
      author='Tranquil IT Systems',
      author_email='contact@tranquil.it',
      url='http://dev.tranquil.it/index.html',
      classifiers=[
        'Development Status :: 3 - Beta',
        'Intended Audience :: System Administrators',
        'Operating System :: Microsoft :: Windows :: Windows 95/98/2000/XP/2003/7',
        'Topic :: System',
      ],

      packages=['waptcore'],
      #package_data={'waptcore': ['data/*.xml']},
      install_requires=['iniparse','request','flask','rocket','zmq','winsys','dnspython', 'psutil', ''],
      )