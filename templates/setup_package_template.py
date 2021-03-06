# -*- coding: utf-8 -*-
from setuphelpers import *

# registry key(s) where WAPT will find how to remove the application(s)
uninstallkey = [%(uninstallkey)s]

# command(s) to launch to remove the application(s)
uninstallstring = []

# list of required parameters names (string) which can be used during install
required_params = []


def install():
    # if you want to modify the keys depending on environment (win32/win64... params..)
    global uninstallkey
    global uninstallstring

    print('installing %(packagename)s')
    run(r'"%(installer)s" %(silentflags)s')
