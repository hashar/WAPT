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
__version__="0.8.26"

import os,sys
try:
    wapt_root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__),'..'))
except:
    wapt_root_dir = 'c:/tranquilit/wapt'

sys.path.append(os.path.join(wapt_root_dir))
sys.path.append(os.path.join(wapt_root_dir,'lib'))
sys.path.append(os.path.join(wapt_root_dir,'lib','site-packages'))

from flask import request, Flask,Response, send_from_directory, session, g, redirect, url_for, abort, render_template, flash
import time
import json
import hashlib
import pymongo
from pymongo import MongoClient
from werkzeug import secure_filename
from functools import wraps
import logging
import ConfigParser
import logging
import codecs
import zipfile
import platform
import pprint
import socket
import requests
import subprocess
import tempfile
import traceback

from rocket import Rocket

import thread
import threading

from waptpackage import *
import pefile

from optparse import OptionParser
usage="""\
%prog -c configfile [action]

WAPTServer daemon.

action is either :
  <nothing> : run service in foreground
  install   : install as a Windows service managed by nssm

"""

parser=OptionParser(usage=usage,version='waptserver.py ' + __version__)
parser.add_option("-c","--config", dest="configfile", default=os.path.join(wapt_root_dir,'waptserver','waptserver.ini'), help="Config file full path (default: %default)")
parser.add_option("-l","--loglevel", dest="loglevel", default=None, type='choice',  choices=['debug','warning','info','error','critical'], metavar='LOGLEVEL',help="Loglevel (default: warning)")

(options,args)=parser.parse_args()

# setup logging
logger = logging.getLogger()
logging.basicConfig(format='%(asctime)s %(levelname)s %(message)s')

def setloglevel(logger,loglevel):
    """set loglevel as string"""
    if loglevel in ('debug','warning','info','error','critical'):
        numeric_level = getattr(logging, loglevel.upper(), None)
        if not isinstance(numeric_level, int):
            raise ValueError('Invalid log level: %s' % loglevel)
        logger.setLevel(numeric_level)

# force loglevel
if options.loglevel is not None:
    setloglevel(logger,options.loglevel)

log_directory = os.path.join(wapt_root_dir,'log')
if not os.path.exists(log_directory):
    os.mkdir(log_directory)

hdlr = logging.StreamHandler(sys.stdout)
hdlr.setFormatter(logging.Formatter('%(asctime)s %(levelname)s %(message)s'))
logger.addHandler(hdlr)

hdlr = logging.FileHandler(os.path.join(log_directory,'waptserver.log'))
hdlr.setFormatter(logging.Formatter('%(asctime)s %(levelname)s %(message)s'))
logger.addHandler(hdlr)

# read configuration from waptserver.ini
config = ConfigParser.RawConfigParser()
if os.path.exists(options.configfile):
    config.read(options.configfile)
else:
    raise Exception("FATAL. Couldn't open config file : " + options.configfile)

#default mongodb configuration for wapt
mongodb_port = "38999"
mongodb_ip = "127.0.0.1"

wapt_folder = ""
wapt_user = ""
wapt_password = ""

waptserver_port = 8080
waptservice_port = 8088

if config.has_section('options'):
    if config.has_option('options', 'wapt_user'):
        wapt_user = config.get('options', 'wapt_user')
    else:
        wapt_user='admin'

    if config.has_option('options', 'waptserver_port'):
        waptserver_port = config.get('options', 'waptserver_port')

    if config.has_option('options', 'wapt_password'):
        wapt_password = config.get('options', 'wapt_password')
    else:
        raise Exception ('No waptserver admin password set in wapt-get.ini configuration file')

    if config.has_option('options', 'mongodb_port'):
        mongodb_port = config.get('options', 'mongodb_port')

    if config.has_option('options', 'mongodb_ip'):
        mongodb_ip = config.get('options', 'mongodb_ip')

    if config.has_option('options', 'wapt_folder'):
        wapt_folder = config.get('options', 'wapt_folder')
        if wapt_folder.endswith('/'):
            wapt_folder = wapt_folder[:-1]

    if options.loglevel is None and config.has_option('options', 'loglevel'):
        loglevel = config.get('options', 'loglevel')
        setloglevel(logger,loglevel)

else:
    raise Exception ("FATAL, configuration file " + config_file + " has no section [options]. Please check Waptserver documentation")

if not wapt_folder:
    wapt_folder = os.path.join(wapt_root_dir,'waptserver','repository','wapt')

waptsetup = os.path.join(wapt_folder, 'waptsetup.exe')

# Setup initial directories
if os.path.exists(wapt_folder)==False:
    try:
        os.makedirs(wapt_folder)
    except:
        raise Exception("Folder missing : %s" % wapt_folder)
if os.path.exists(wapt_folder + '-host')==False:
    try:
        os.makedirs(wapt_folder + '-host')
    except:
        raise Exception("Folder missing : %s-host" % wapt_folder )
if os.path.exists(wapt_folder + '-group')==False:
    try:
        os.makedirs(wapt_folder + '-group')
    except:
        raise Exception("Folder missing : %s-group" % wapt_folder )

ALLOWED_EXTENSIONS = set(['wapt'])

app = Flask(__name__,static_folder='./templates/static')

def hosts():
    """Opens a new database connection if there is none yet for the
    current application context.
    """
    if not hasattr(g, 'client'):
        try:
            logger.debug('Connecting to mongo db %s:%s'%(mongodb_ip, int(mongodb_port)))
            g.client = MongoClient(mongodb_ip, int(mongodb_port))
            g.db = g.client.wapt
            g.hosts = g.db.hosts
            g.hosts.ensure_index('uuid',unique=True)
            g.hosts.ensure_index('computer_name',unique=False)
        except Exception as e:
            raise Exception(u"Could not connect do mongodb database: %s"%(repr(e),))
    return g.hosts

@app.teardown_appcontext
def close_db(error):
    """Closes the database again at the end of the request."""
    if hasattr(g, 'client'):
        logger.debug('Disconnected from mongodb')
        del g.hosts
        del g.db
        del g.client

def get_host_data(uuid, filter = {}, delete_id = True):
    if filter:
        data = hosts().find_one({ "uuid": uuid}, filter)
    else:
        data = hosts().find_one({ "uuid": uuid})
    if data and delete_id:
        data.pop("_id")
    return data


@app.route('/')
def index():
    return render_template("index.html")


@app.route('/info')
def informations():
    informations = {}
    informations["server_version"] = __version__
    if os.path.exists(waptsetup):
        pe = pefile.PE(waptsetup)
        informations["client_version"] =  pe.FileInfo[0].StringTable[0].entries['ProductVersion'].strip()

    return Response(response=json.dumps(informations),
                     status=200,
                     mimetype="application/json")


@app.route('/wapt/')
def wapt_listing():
    return render_template('listing.html',data=data)


@app.route('/hosts')
@app.route('/json/host_list',methods=['GET'])
def get_host_list():
    list_hosts = []
    data = request.args
    query = {}
    search_filter = ""
    search = ""
    try:
        if "package_error" in data.keys() and data['package_error'] == "true":
            query["packages.install_status"] = "ERROR"
        if "need_upgrade" in data.keys() and data['need_upgrade'] == "true":
            query["update_status.upgrades"] = {"$exists": "true", "$ne" :[]}
        if "q" in data.keys():
            search = data['q'].lower()
        if "filter" in data.keys():
            search_filter = data['filter'].split(',')

        #{"host":1,"dmi":1,"uuid":1, "wapt":1, "update_status":1,"last_query_date":1}

        for host in hosts().find( query):
            host.pop("_id")
            if search_filter:
                for key in search_filter:
                    if key in host and search in json.dumps(host[key]).lower():
                        host["softwares"] = ""
                        host["packages"] = ""
                        list_hosts.append(host)
                        continue
            elif search and search in json.dumps(host).lower():
                host["softwares"] = ""
                host["packages"] = ""
                list_hosts.append(host)
            elif search == "":
                host["softwares"] = ""
                host["packages"] = ""
                list_hosts.append(host)

        result = list_hosts
    except Exception as e:
        result = dict(status='ERROR',message='%s: %s'%('hosts',e),result=None)

    return Response(response=json.dumps(result),
                     status=200,
                     mimetype="application/json")


def update_data(data):
    data['last_query_date'] = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())
    host = get_host_data(data["uuid"],delete_id=False)
    if host:
        hosts().update({"_id" : host['_id'] }, {"$set": data})
    else:
        host_id = hosts().insert(data)
    return get_host_data(data["uuid"],filter={"uuid":1,"host":1})


@app.route('/add_host',methods=['POST','GET'])
@app.route('/update_host',methods=['POST'])
def update_host():
    """Update localstatus of computer, and return known registration info"""
    try:
        data = json.loads(request.data)
        if data:
            uuid = data["uuid"]
            if uuid:
                logger.info('Update host %s status'%(uuid,))
                result = dict(status='OK',message="update_host: No data supplied",result=update_data(data))
            else:
                result = dict(status='ERROR',message="update_host: No uuid supplied")
        else:
            result = dict(status='ERROR',message="update_host: No data supplied")

    except Exception as e:
        result = dict(status='ERROR',message='%s: %s'%('update_host',e),result=None)

    # backward... to fix !
    if result['status'] == 'OK':
        return Response(response=json.dumps(result['result']),
                         status=200,
                         mimetype="application/json")
    else:
        return Response(response=json.dumps(result),
                         status=200,
                         mimetype="application/json")


@app.route('/delete_host/<string:uuid>')
def delete_host(uuid=""):
    try:
        hosts().remove({'uuid': uuid })
        data = get_host_data(uuid)
        result = dict(status='OK',message=json.dumps(data))
    except Exception as e:
        result = dict(status='ERROR',message=u"%s"%e)
    return Response(response=json.dumps(data),
                 status=200,
                 mimetype="application/json")


# to fix !
@app.route('/client_software_list/<string:uuid>')
def get_client_software_list(uuid=""):
    softwares = get_host_data(uuid, filter={"softwares":1})
    if 'softwares' in softwares:
        return  Response(response=json.dumps(softwares['softwares']),
                         status=200,
                         mimetype="application/json")
    else:
        return "{}"


def packagesFileToList(pathTofile):
    listPackages = codecs.decode(zipfile.ZipFile(pathTofile).read(name='Packages'),'utf-8')
    packages = []

    def add_package(lines):
        package = PackageEntry()
        package.load_control_from_wapt(lines)
        package.filename = package.make_package_filename()
        packages.append(package)

    lines = []
    for line in listPackages.splitlines():
        # new package
        if line.strip()=='':
            add_package(lines)
            lines = []
            # add ettribute to current package
        else:
            lines.append(line)

    if lines:
        add_package(lines)
        lines = []

    packages.sort()
    return packages


@app.route('/host_packages/<string:uuid>')
def host_packages(uuid=""):
    try:
        packages = get_host_data(uuid, {"packages":1})
        if not packages:
            raise Exception('No host with uuid %s'%uuid)
        repo_packages = packagesFileToList(os.path.join(wapt_folder, 'Packages'))
        if 'packages' in packages:
            for p in packages['packages']:
                package = PackageEntry()
                package.load_control_from_dict(p)
                matching = [ x for x in repo_packages if package.package == x.package ]
                if matching:
                    if package < matching[-1]:
                        p['install_status'] = 'NEED-UPGRADE'
        result = dict(status='OK',message='%i packages for host uuid: %s'%(len(packages['packages']),uuid),result = packages['packages'])
    except Exception as e:
        result = dict(status='ERROR',message='%s: %s'%('host_packages',e),result=None)

    return Response(response=json.dumps(result),
                     status=200,
                     mimetype="application/json")


@app.route('/client_package_list/<string:uuid>')
def get_client_package_list(uuid=""):
    try:
        packages = get_host_data(uuid, {"packages":1})
        if not packages:
            raise Exception('No host with uuid %s'%uuid)
        repo_packages = packagesFileToList(os.path.join(wapt_folder, 'Packages'))
        if 'packages' in packages:
            for p in packages['packages']:
                package = PackageEntry()
                package.load_control_from_dict(p)
                matching = [ x for x in repo_packages if package.package == x.package ]
                if matching:
                    if package < matching[-1]:
                        p['install_status'] = 'NEED-UPGRADE'
        result = dict(status='OK',message='%i packages for host uuid: %s'%(len(packages['packages']),uuid),result = packages['packages'])
        return Response(response=json.dumps(packages['packages']),
                         status=200,
                         mimetype="application/json")
    except Exception as e:
        result = dict(status='ERROR',message='%s: %s'%('get_client_package_list',e),result=None)

    return Response(response=json.dumps(packages['packages']),
                     status=200,
                     mimetype="application/json")


def requires_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.authorization

        if not auth:
            logger.info('no credential given')
            return authenticate()

        logging.debug("authenticating : %s" % auth.username)
        if not check_auth(auth.username, auth.password):
            return authenticate()
        logger.info("user %s authenticated" % auth.username)
        return f(*args, **kwargs)
    return decorated


@app.route('/upload_package/<string:filename>',methods=['POST'])
@requires_auth
def upload_package(filename=""):
    try:
        tmp_target = ''
        if request.method == 'POST':
            if filename and allowed_file(filename):
                tmp_target = os.path.join(wapt_folder, secure_filename(filename+'.tmp'))
                target = os.path.join(wapt_folder, secure_filename(filename))
                with open(tmp_target, 'wb') as f:
                    f.write(request.stream.read())
                if not os.path.isfile(tmp_target):
                    result = dict(status='ERROR',message='Problem during upload')
                else:
                    if PackageEntry().load_control_from_wapt(tmp_target):
                        if os.path.isfile(target):
                            os.unlink(target)
                        os.rename(tmp_target,target)
                        data = update_packages(wapt_folder)
                        result = dict(status='OK',message='%s uploaded, %i packages analysed'%(filename,len(data['processed'])),result=data)
                    else:
                        result = dict(status='ERROR',message='Not a valid wapt package')
                        os.unlink(tmp_target)
            else:
                result = dict(status='ERROR',message='Wrong file type')
        else:
            result = dict(status='ERROR',message='Unsupported method')
    except:
        # remove temporary
        if os.path.isfile(tmp_target):
            os.unlink(tmp_target)
        e = sys.exc_info()
        logger.critical(repr(traceback.format_exc()))
        result = dict(status='ERROR',message='unexpected: %s'%(e,))
    return  Response(response=json.dumps(result),
                         status=200,
                         mimetype="application/json")


@app.route('/upload_host',methods=['POST'])
@requires_auth
def upload_host():
    try:
        file = request.files['file']
        if file:
            logger.debug('uploading host file : %s' % file)
            if file and allowed_file(file.filename):
                filename = secure_filename(file.filename)
                tmp_target = os.path.join(wapt_folder+'-host', filename+'.tmp')
                target = os.path.join(wapt_folder+'-host', filename)
                file.save(tmp_target)
                if os.path.isfile(tmp_target):
                    try:
                        # try to read attributes...
                        entry = PackageEntry().load_control_from_wapt(tmp_target)
                        if os.path.isfile(target):
                            os.unlink(target)
                        os.rename(tmp_target,target)
                        result = dict(status='OK',message='File %s uploaded to %s'%(file.filename,target))
                    except:
                        if os.path.isfile(tmp_target):
                            os.unlink(tmp_target)
                        raise
                else:
                    result = dict(status='ERROR',message='No data received')
            else:
                result = dict(status='ERROR',message='Wrong file type')
        else:
            result = dict(status='ERROR',message='No package file provided in request')
    except:
        # remove temporary
        if os.path.isfile(tmp_target):
            os.unlink(tmp_target)
        e = sys.exc_info()
        logger.critical(repr(traceback.format_exc()))
        result = dict(status='ERROR',message='upload_host: %s'%(e,))
    return  Response(response=json.dumps(result),
                         status=200,
                         mimetype="application/json")


@app.route('/upload_waptsetup',methods=['POST'])
@requires_auth
def upload_waptsetup():
    logger.debug("Entering upload_waptsetup")
    tmp_target = None
    try:
        if request.method == 'POST':
            file = request.files['file']
            if file and "waptsetup.exe" in file.filename :
                filename = secure_filename(file.filename)
                tmp_target = os.path.join(wapt_folder, secure_filename('.'+filename))
                target = os.path.join(wapt_folder, secure_filename(filename))
                file.save(tmp_target)
                if not os.path.isfile(tmp_target):
                    result = dict(status='ERROR',message='Problem during upload')
                else:
                    os.rename(tmp_target,target)
                    result = dict(status='OK',message='%s uploaded'%(filename,))
            else:
                result = dict(status='ERROR',message='Wrong file name')
        else:
            result = dict(status='ERROR',message='Unsupported method')
    except:
        e = sys.exc_info()
        if tmp_target and os.path.isfile(tmp_target):
            os.unlink(tmp_target)
        result = dict(status='ERROR',message='unexpected: %s'%(e,))
    return  Response(response=json.dumps(result),
                         status=200,
                         mimetype="application/json")


@app.route('/waptupgrade_host/<string:ip>')
@requires_auth
def waptupgrade_host(ip):
    try:
        result = {}
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(1)
            s.connect((ip,waptservice_port))
            s.close
            if ip and waptservice_port:
                logger.info( "Upgrading %s..." % ip)
                try:
                    httpreq = requests.get("http://%s:%d/waptupgrade.json" % ( ip, waptservice_port),proxies=None)
                    httpreq.raise_for_status()
                    result = {'status' : 'OK', 'message': u"%s" % httpreq.text }
                except Exception as e:
                    logger.warning(u'%s'%e)
                    r = requests.get("http://%s:%d/waptupgrade" % ( ip, waptservice_port),proxies=None)
                    if "OK" in r.text.upper():
                        result = {  'status' : 'OK', 'message': u"%s" % r.text }
                    else:
                        result = {  'status' : 'ERROR', 'message': u"%s" % r.text }
            else:
                raise Exception(u"Le port de waptservice n'est pas défini")

        except Exception as e:
            raise Exception("Impossible de joindre le waptservice: %s" % e)

    except Exception, e:
            result = { 'status' : 'ERROR', 'message': u"%s" % e  }

    return  Response(response=json.dumps(result),
                         status=200,
                         mimetype="application/json")


@app.route('/install_package')
@app.route('/install_package.json')
@requires_auth
def install_package():
    try:
        result = {}
        try:
            package = request.args['package']
            ip = request.args['host']
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(1)
            s.connect((ip,waptservice_port))
            s.close
            if ip and waptservice_port:
                logger.info( "installing %s on %s ..." % (package,ip))
                data = json.loads(requests.get("http://%s:%d/install.json?package=%s" % ( ip, waptservice_port,package),proxies=None).text)
                result = dict(message=data,status='OK')
            else:
                raise Exception(u"Le port de waptservice n'est pas défini")

        except Exception as e:
            raise Exception("Impossible de joindre le web service: %s" % e)

    except Exception, e:
            result = { 'status' : 'ERROR', 'message': u"%s" % e  }
    return  Response(response=json.dumps(result),
                         status=200,
                         mimetype="application/json")


@app.route('/remove_package')
@app.route('/remove_package.json')
@requires_auth
def remove_package():
    try:
        result = {}
        try:
            package = request.args['package']
            ip = request.args['host']
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(1)
            s.connect((ip,waptservice_port))
            s.close
            if ip and waptservice_port:
                logger.info( "removing %s on %s ..." % (package,ip))
                httpreq = requests.get("http://%s:%d/remove.json?package=%s" % ( ip, waptservice_port,package),proxies=None)
                httpreq.raise_for_status()
                data = json.loads(httpreq.text)
                result = dict(message=data,status='OK')
            else:
                raise Exception(u"Le port de waptservice n'est pas défini")

        except Exception as e:
            raise Exception("Impossible de joindre le waptservice du poste: %s" % e)

    except Exception, e:
            result = { 'status' : 'ERROR', 'message': u"%s" % e  }
    return  Response(response=json.dumps(result),
                         status=200,
                         mimetype="application/json")


@app.route('/host_tasks')
@app.route('/host_tasks.json')
@requires_auth
def host_tasks():
    try:
        result = {}
        try:
            ip = request.args['host']
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(1)
            s.connect((ip,waptservice_port))
            s.close
            if ip and waptservice_port:
                data = json.loads(requests.get("http://%s:%d/tasks.json" % ( ip, waptservice_port),proxies=None).text)
                result = dict(message=data,status='OK')
            else:
                raise Exception(u"Le port de waptservice n'est pas défini")

        except Exception as e:
            raise Exception("Impossible de joindre le web service: %s" % e)

    except Exception, e:
            result = { 'status' : 'ERROR', 'message': u"%s" % e  }
    return  Response(response=json.dumps(result),
                         status=200,
                         mimetype="application/json")


@app.route('/host_taskkill')
@app.route('/host_taskkill.json')
@requires_auth
def host_taskkill():
    try:
        result = {}
        try:
            ip = request.args['host']
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(1)
            s.connect((ip,waptservice_port))
            s.close
            if ip and waptservice_port:
                data = json.loads(requests.get("http://%s:%d/cancel_running_task.json" % ( ip, waptservice_port),proxies=None).text)
                result = dict(message=data,status='OK')
            else:
                raise Exception(u"Le port de waptservice n'est pas défini")

        except Exception as e:
            raise Exception("Impossible de joindre le web service: %s" % e)

    except Exception, e:
            result = { 'status' : 'ERROR', 'message': u"%s" % e  }
    return  Response(response=json.dumps(result),
                         status=200,
                         mimetype="application/json")


@app.route('/hosts_by_group/<string:name>')
@requires_auth
def get_hosts_by_group(name=""):
    try:
        list_hosts  =  []
        os.chdir(wapt_folder + '-host')
        hosts = [f for f in os.listdir('.') if os.path.isfile(f) and f.endswith('.wapt')]
        package = PackageEntry()
        for h in hosts:
            package.load_control_from_wapt(h)
            if name in package.depends.split(','):
                list_hosts.append({"computer_fqdn":package.package})

        return  Response(response=json.dumps(list_hosts),
                         status=200,
                         mimetype="application/json")
    except:
        e = sys.exc_info()
        return str(e)
    return "Unsupported method"


@app.route('/upgrade_host/<string:ip>')
@requires_auth
def upgrade_host(ip):
    """Proxy the wapt upgrade action to the client"""
    try:
        result = {}
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(1)
            s.connect((ip,waptservice_port))
            s.close
            if ip and waptservice_port:
                logger.info( "Upgrading %s..." % ip)
                try:
                    result = json.loads(requests.get("http://%s:%d/upgrade.json" % ( ip, waptservice_port),proxies=None).text)
                except Exception as e:
                    # try the old behaviour for wapt client < 0.8.10
                    logger.warning(u"%s"%e)
                    r = requests.get("http://%s:%d/upgrade" % ( ip, waptservice_port),proxies=None)
                    if "OK" in r.text.upper():
                        result = {  'status' : 'OK', 'message': u"%s" % r.text }
                    else:
                        result = {  'status' : 'ERROR', 'message': u"%s" % r.text }

            else:
                raise Exception(u"Le port de waptservice n'est pas défini")

        except Exception as e:
            raise  Exception("Impossible de joindre le web service: %s" % e)

    except Exception, e:
            result = { 'status' : 'ERROR', 'message': u"%s" % e  }
    return  Response(response=json.dumps(result),
                         status=200,
                         mimetype="application/json")


def install_wapt(computer_name,authentication_file):
    cmd = '/usr/bin/smbclient -G -E -A %s  //%s/IPC$ -c listconnect ' % (authentication_file, computer_name)
    try:
        subprocess.check_output(cmd,stderr=subprocess.STDOUT,shell=True)
    except subprocess.CalledProcessError as e:
        if "NT_STATUS_LOGON_FAILURE" in e.output:
            raise Exception("Mauvais identifiants")
        if "NT_STATUS_CONNECTION_REFUSED" in e.output:
            raise Exception("Partage IPC$ non accessible")

        raise Exception(u"%s" % e.output)

    cmd = '/usr/bin/smbclient -A "%s" //%s/c\\$ -c "put waptsetup.exe" ' % (authentication_file, computer_name)
    print subprocess.check_output(cmd,shell=True)

    cmd = '/usr/bin/winexe -A "%s"  //%s  "c:\\waptsetup.exe  /MERGETASKS=""useWaptServer,autorunTray"" /VERYSILENT"  ' % (authentication_file, computer_name)
    print subprocess.check_output(cmd,shell=True)

#    cmd = '/usr/bin/smbclient -A "%s" //%s/c\\$ -c "cd wapt ; put wapt-get.ini ; exit" ' % (authentication_file, computer_name)
#    print subprocess.check_output(cmd,shell=True)

    cmd = '/usr/bin/winexe -A "%s"  //%s  "c:\\wapt\\wapt-get.exe register"' % (authentication_file, computer_name)
    print subprocess.check_output(cmd,shell=True)

    cmd = '/usr/bin/winexe -A "%s"  //%s  "c:\\wapt\\wapt-get.exe --version"' % (authentication_file, computer_name)
    return subprocess.check_output(cmd,shell=True)


@app.route('/deploy_wapt',methods=['POST'])
@requires_auth
def deploy_wapt():
    try:
        result = {}
        if platform.system() != 'Linux':
            raise Exception(u'Le serveur wapt doit être executé sous Linux')
        if subprocess.call('which smbclient',shell=True) != 0:
            raise Exception(u"smbclient n'est pas installé sur le serveur wapt")
        if subprocess.call('which winexe',shell=True) != 0:
            raise Exception(u"winexe n'est pas installé sur le serveur wapt")

        if request.method == 'POST':
            d = json.loads(request.data)
            if 'auth' not in d:
                raise Exception("Les informations d'authentification sont manquantes")
            if 'computer_fqdn' not in d:
                raise Exception(u"Il n'y a aucuns ordinateurs de renseigné")

            auth_file = tempfile.mkstemp("wapt")[1]
            try:
                with open(auth_file, 'w') as f:
                    f.write('username = %s\npassword = %s\ndomain = %s\n'% (
                        d['auth']['username'],
                        d['auth']['password'],
                        d['auth']['domain']))

                os.chdir(wapt_folder)

                message = install_wapt(d['computer_fqdn'],auth_file)

                result = { 'status' : 'OK' , 'message': message}
            finally:
                os.unlink(auth_file)

        else:
            raise Exception(u"methode http non supportée")

    except Exception, e:
        result = { 'status' : 'ERROR', 'message': u"%s" % e  }

    return  Response(response=json.dumps(result),
                         status=200,
                         mimetype="application/json")


@app.route('/login',methods=['POST'])
def login():
    try:
        if request.method == 'POST':
            d= json.loads(request.data)
            if "username" in d and "password" in d:
                if check_auth(d["username"], d["password"]):
                    if "newPass" in d:
                        global wapt_password
                        wapt_password = hashlib.sha512(d["newPass"]).hexdigest()
                        config.set('options', 'wapt_password', wapt_password)
                        with open(os.path.join(wapt_root_dir,'waptserver','waptserver.ini'), 'wb') as configfile:
                            config.write(configfile)
                    return "True"
            return "False"
        else:
            return "Unsupported method"
    except:
        e = sys.exc_info()
        return str(e)


def allowed_file(filename):
    return '.' in filename and \
           filename.rsplit('.', 1)[1] in ALLOWED_EXTENSIONS


@app.route('/delete_package/<string:filename>')
@requires_auth
def delete_package(filename=""):
    fullpath = os.path.join(wapt_folder,filename)
    try:
        if os.path.isfile(fullpath):
            os.unlink(fullpath)
            data = update_packages(wapt_folder)
            if os.path.isfile("%s.zsync"%(fullpath,)):
                os.unlink("%s.zsync"%(fullpath,))
            result = dict(status='OK',message="Package deleted %s" % (fullpath,),result=data)
        else:
            result = dict(status='ERROR',message="The file %s doesn't exist in wapt folder (%s)" % (filename, wapt_folder))

    except Exception, e:
        result = { 'status' : 'ERROR', 'message': u"%s" % e  }

    return  Response(response=json.dumps(result),
                         status=200,
                         mimetype="application/json")


@app.route('/wapt/<string:input_package_name>')
def get_wapt_package(input_package_name):
    logger.info( "get wapt package : "+ input_package_name)
    global wapt_folder
    package_name = secure_filename(input_package_name)
    r =  send_from_directory(wapt_folder, package_name)
    logger.info("checking if content-length is there or not")
    if 'content-length' not in r.headers:
        r.headers.add_header('content-length', int(os.path.getsize(os.path.join(wapt_folder,package_name))))
        logger.info('adding content-length')
    logger.info(pprint.pformat(r.headers))
    return r


@app.route('/wapt-host/<string:input_package_name>')
def get_host_package(input_package_name):
    global wapt_folder
    #TODO straighten this -host stuff
    host_folder = wapt_folder + '-host'
    logger.info( "get host package : " + input_package_name)
    package_name = secure_filename(input_package_name)
    r =  send_from_directory(host_folder, package_name)
    # on line content-length is not added to the header.
    logger.info(pprint.pformat(r.headers))

    logger.info("checking if content-length is there or not")
    if 'Content-Length' not in r.headers:
        r.headers.add_header('Content-Length', int(os.path.getsize(os.path.join(host_folder,package_name))))
        logger.info('content-length added')
    logger.info(pprint.pformat(r.headers))
    return r


@app.route('/wapt-group/<string:input_package_name>')
def get_group_package(input_package_name):
    global wapt_folder
    #TODO straighten this -group stuff
    group_folder = wapt_folder + '-group'
    logger.info( "get group package : " + input_package_name)
    package_name = secure_filename(input_package_name)
    r =  send_from_directory(group_folder, package_name)
    # on line content-length is not added to the header.
    if 'content-length' not in r.headers:
        r.headers.add_header('content-length', os.path.getsize(os.path.join(group_folder + '-group',package_name)))
    return r


def check_auth(username, password):
    """This function is called to check if a username /
    password combination is valid.
    """
    return wapt_user == username and wapt_password == hashlib.sha512(password).hexdigest()


def authenticate():
    """Sends a 401 response that enables basic auth"""
    return Response(
        'You have to login with proper credentials', 401,
        {'WWW-Authenticate': 'Basic realm="Login Required"'})


class CheckHostsWaptService(threading.Thread):
    def __init__(self):
        threading.Thread.__init__(self)
        self.mongoclient = MongoClient(mongodb_ip, int(mongodb_port))
        self.db = mongoclient.wapt
        self.polltimeout = 20

    def get_hosts_ip(self):
        list_hosts = []
        query = {"host.connected_ips":{"$exists": "true", "$ne" :[]}}
        fields = {'host.connected_ips':1,'uuid':1,'host.computer_fqdn':1}
        result = {}
        for host in self.db.hosts.find(query,fields=fields):
            result[host['uuid']] = host['host.connected_ips']
        return result

    def run(self):
        pass


def install_windows_service():
    """Setup waptserver as a windows Service managed by nssm
    >>> install_windows_service()
    """
    import setuphelpers
    from setuphelpers import registry_set,REG_DWORD,REG_EXPAND_SZ,REG_MULTI_SZ,REG_SZ
    datatypes = {
        'dword':REG_DWORD,
        'sz':REG_SZ,
        'expand_sz':REG_EXPAND_SZ,
        'multi_sz':REG_MULTI_SZ,
    }

    if setuphelpers.service_installed('waptserver'):
        if setuphelpers.service_is_running('waptserver'):
            logger.info('Stop running waptserver')
            setuphelpers.run('net stop waptserver')
            while setuphelpers.service_is_running('waptserver'):
                logger.debug('Waiting for waptserver to terminate')
                time.sleep(2)
        logger.info('Unregister existing waptserver')
        setuphelpers.run('sc delete waptserver')

    if setuphelpers.iswin64():
        nssm = os.path.join(wapt_root_dir,'waptservice','win64','nssm.exe')
    else:
        nssm = os.path.join(wapt_root_dir,'waptservice','win32','nssm.exe')

    logger.info('Register new waptserver with nssm')
    setuphelpers.run('"{nssm}" install WAPTServer "{waptpython}" ""{waptserverpy}""'.format(
        waptpython = os.path.abspath(os.path.join(wapt_root_dir,'waptpython.exe')),
        nssm = nssm,
        waptserverpy = os.path.abspath(__file__),
     ))

    # fix some parameters (quotes for path with spaces...
    params = {
        "Description": "sz:Wapt test server",
        "DelayedAutostart": 1,
        "DisplayName" : "sz:WAPTServer",
        "AppStdout" : r"expand_sz:{}".format(os.path.join(log_directory,'waptserver.log')),
        "Parameters\\AppStderr" : r"expand_sz:{}".format(os.path.join(log_directory,'waptserver.log')),
        "Parameters\\AppParameters" : r'expand_sz:"{}"'.format(os.path.abspath(__file__)),
        }

    root = setuphelpers.HKEY_LOCAL_MACHINE
    base = r'SYSTEM\CurrentControlSet\services\WAPTServer'
    for key in params:
        if isinstance(params[key],int):
            (valuetype,value) = ('dword',params[key])
        elif ':' in params[key]:
            (valuetype,value) = params[key].split(':',1)
            if valuetype == 'dword':
                value = int(value)
        else:
            (valuetype,value) = ('sz',params[key])
        fullpath = base+'\\'+key
        (path,keyname) = fullpath.rsplit('\\',1)
        if keyname == '@' or keyname =='':
            keyname = None
        registry_set(root,path,keyname,value,type = datatypes[valuetype])

if __name__ == "__main__":
    if len(sys.argv)>1 and sys.argv[1] == 'doctest':
        import doctest
        sys.exit(doctest.testmod())

    if len(sys.argv)>1 and sys.argv[1] == 'install':
        install_windows_service()
        sys.exit(0)

    debug=False
    if debug==True:
        app.run(host='0.0.0.0',port=30880,debug=True)
    else:
        port = 8080
        server = Rocket(('0.0.0.0', port), 'wsgi', {"wsgi_app":app})
        try:
            logger.info("starting waptserver")
            server.start()
        except KeyboardInterrupt:
            logger.info("stopping waptserver")
            server.stop()
