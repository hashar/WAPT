#-------------------------------------------------------------------------------
# Name:        module1
# Purpose:
#
# Author:      Administrateur
#
# Created:     16/09/2013
# Copyright:   (c) Administrateur 2013
# Licence:     <your licence>
#-------------------------------------------------------------------------------

import os
import pysvn
import subprocess
import ConfigParser
import paramiko
"""
depends pysvn, paramiko

pour le fichier autobuild.ini, la syntaxe est la suivante:
[global]
svn_username=xxxxxx
svn_password=xxxxxxx
checkout_dir=c:\\xxxxxxx
svnroot=https://srvsvn/wapt/trunk
ssh_username = root
ssh_private_key = c:\private\srvwapt_priv.key
ssh_hostname = srvwapt
ssh_log_file = c:\tranquilit\paramiko.log

Installation de pycrypto depuis
http://www.voidspace.org.uk/python/modules.shtml#pycrypto

Installation paramiko avec easy_install
easy_install paramiko

Installation pysvn depuis
http://pysvn.tigris.org/servlets/ProjectDocumentList?folderID=1768

"""

def programfiles32():
    """Return 32bits applications folder."""
    if 'PROGRAMW6432' in os.environ and 'PROGRAMFILES(X86)' in os.environ:
        return os.environ['PROGRAMFILES(X86)']
    else:
        return os.environ['PROGRAMFILES']


def ssl_server_trust_prompt( trust_dict ):
    return True, trust_dict['failures'], True

# TODO : net stop waptservice
# TODO : taskkill /f /im "wapttray.exe"
# TODO : taskkill /f /im "waptconsole.exe"


client = pysvn.Client()
config_file = "c:\\private\\autobuild.ini"
config = ConfigParser.RawConfigParser()

def get_required_param(param_name,section='global'):
    global config
    if config.has_option(section, param_name):
        return config.get(section, param_name)
    else:
        raise Exception ("missing parameter %s in section %s config file",(param_name,section))


if os.path.exists(config_file):
    config.read(config_file)
else:
    raise Exception("FATAL. Couldn't open config file : " + config_file)

if config.has_section('global'):
    svn_username = get_required_param('svn_username')
    svn_password = get_required_param('svn_password')
    checkout_dir = get_required_param('checkout_dir')
    svnroot = get_required_param('svnroot')
    ssh_username = get_required_param('ssh_username')
    ssh_private_key = get_required_param('ssh_private_key')
    ssh_hostname = get_required_param('ssh_hostname')
    ssh_log_file = get_required_param('ssh_log_file')
    ksign = get_required_param('ksign')
else:
    raise Exception ('missing [global] section')

#check out the current version of the pysvn project
client.callback_ssl_server_trust_prompt = ssl_server_trust_prompt
client.set_default_username(svn_username)
client.set_default_password(svn_password)


if os.path.exists(os.path.dirname(checkout_dir))==False:
    os.mkdir(os.path.dirname(checkout_dir))

if os.path.exists(checkout_dir):
    print "checkout_dir already exists"
    try:
        rev = client.info (checkout_dir).get("revision").number
        print "%s already exists and it is a checkout directory" % checkout_dir
    except:
        raise Exception('Checkout directory %s exists and is not a svn directory, please delete it' % checkout_dir)


print "checkout du projet"

print subprocess.check_output('svn co --username=%s --password=%s --trust-server-cert --non-interactive %s %s' % (svn_username, svn_password,svnroot,checkout_dir),shell=True)

rev =  client.info (checkout_dir).get("revision").number

print "building waptsetup_%s.exe" % rev

issfile = os.path.join(checkout_dir,'waptsetup','waptsetup.iss')
print "running waptsetup for iss file : %s " % issfile
issc_binary = os.path.join(programfiles32(),'Inno Setup 5','ISCC.exe')

print subprocess.check_output([issc_binary,"/skSign=%s" % ksign,'/fwaptsetup_rev%s' % rev,"%s"%issfile])

localfile = os.path.join(os.path.dirname(issfile),'waptsetup_rev%s.exe' % rev )
remotefile = os.path.join('/var/www/wapt/nightly/','waptsetup_rev%s.exe' % rev)

print "copying %s to remote server" % localfile
print remotefile
paramiko.util.log_to_file(ssh_log_file)
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(
            paramiko.AutoAddPolicy())
my_key = paramiko.DSSKey.from_private_key_file(ssh_private_key)
ssh.connect(ssh_hostname,port=22,username=ssh_username,pkey=my_key,timeout=10)
sftp = ssh.open_sftp()
sftp.put(remotepath=remotefile, localpath=localfile)
sftp.close()
ssh.close()


