#!/usr/bin/python
# -*- coding: utf-8 -*-
# -----------------------------------------------------------------------
#    This file is part of WAPT
#    Copyright (C) 2013  Tranquil IT Systems http://www.tranquil.it
#    WAPT aims to help Windows systems administrators to deploy
#    setup and update applications on users PC.
#
#    WAPT is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    WAPT is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with WAPT.  If not, see <http://www.gnu.org/licenses/>.
#
# -----------------------------------------------------------------------

import os,glob,sys,stat
import shutil
import fileinput
import platform, errno
import subprocess

def replaceAll(file,searchExp,replaceExp):
    for line in fileinput.input(file, inplace=1):
        if searchExp in line:
            line = line.replace(searchExp,replaceExp)
        sys.stdout.write(line)

wapt_source_dir = os.path.abspath('../..')
print "source tree : %s" % wapt_source_dir

source_dir = os.path.abspath('..')
shutil.copyfile(os.path.join(wapt_source_dir,'waptpackage.py'),os.path.join(source_dir,'waptpackage.py'))
shutil.copyfile(os.path.join(wapt_source_dir,'waptzsync.py'),os.path.join(source_dir,'waptzsync.py'))

for line in open('%s/waptpackage.py'% source_dir):
    if '__version__' in line:
        wapt_version = line.split('=')[1].replace('"','').replace("'","").replace('\n','').replace(' ','').replace('\r','')

if not wapt_version:
    print 'version non trouvée dans %s/waptpackage.py, la version est mise a 0.0.0 par défault.'%os.path.abspath('..')
    wapt_version = '0.0.0'

control_file = './builddir/DEBIAN/control'
rsync_option = " --exclude '.svn' --exclude 'deb' -ap"
rsync_source = source_dir
rsync_destination = './builddir/opt/wapt/'
rsync_command = '/usr/bin/rsync %s %s %s'%(rsync_option,rsync_source,rsync_destination)

for filename in glob.glob("tis-waptrepo*.deb"):
    print "destruction de %s"%filename
    os.remove(filename)
if os.path.exists("builddir"):
    shutil.rmtree("builddir")
print 'création de l\'arborescence'
os.makedirs("builddir")
os.makedirs("builddir/DEBIAN")
os.makedirs("builddir/opt")
os.makedirs("builddir/opt/wapt")
os.makedirs("builddir/opt/wapt/waptrepo/")

#adding version info in VERSION file
rev=''
output = subprocess.check_output('/usr/bin/svn info',shell=True)
for line in output.split('\n'):
    if 'Revision:' in line:
        rev = 'rev%s' % line.split(':')[1].strip()
version_file = open(os.path.join('./builddir/opt/wapt/waptrepo','VERSION'),'w')
version_file.write(rev)
version_file.close()

print 'copie des fichiers waptrepo'
os.system(rsync_command)
print 'copie des fichiers control et postinst'
try:
    shutil.copyfile('./DEBIAN/control','./builddir/DEBIAN/control')
except Exception as e:
    print 'erreur: \n%s'%e
    exit (0)
try:
    shutil.copyfile('./DEBIAN/postinst','./builddir/DEBIAN/postinst')
except Exception as e:
    print 'erreur: \n%s'%e
    exit(0)
print 'inscription de la version dans le fichier de control'
replaceAll(control_file,'0.0.7',wapt_version + '-' + rev)

print 'création du paquet Deb'
os.chmod('./builddir/DEBIAN/postinst',stat.S_IRWXU| stat.S_IXGRP | stat.S_IRGRP | stat.S_IROTH | stat.S_IXOTH)
dpkg_command = 'dpkg-deb --build builddir tis-waptrepo-%s-%s.deb'% (wapt_version ,rev)
os.system(dpkg_command)
shutil.rmtree("builddir")
