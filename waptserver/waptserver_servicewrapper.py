### Run Python scripts as a service example (ryrobes.com)
### Usage : python aservice.py install (or / then start, stop, remove)

import win32service
import win32serviceutil
import win32api
import win32con
import win32event
import win32evtlogutil
import os, sys, string, time


sys.path.append("c:\wapt\lib")
sys.path.append("c:\wapt\waptserver")
sys.path.append("c:\wapt\lib\site-packages")

import  cheroot.wsgi


class aservice(win32serviceutil.ServiceFramework):

    _svc_name_ = "WAPTServer"
    _svc_display_name_ = "WAPT Server"
    _svc_description_ = "WAPTServer for configuring and deploying wapt packages on a network"
    _svc_deps_ = ["WAPTMongodb"]
    server = None

    def __init__(self, args):
        win32serviceutil.ServiceFramework.__init__(self, args)
        self.hWaitStop = win32event.CreateEvent(None, 0, 0, None)

    def SvcStop(self):

        self.ReportServiceStatus(win32service.SERVICE_STOP_PENDING)
        win32event.SetEvent(self.hWaitStop)
        self.server.stop()

    def SvcDoRun(self):
        import servicemanager
        servicemanager.LogMsg(servicemanager.EVENTLOG_INFORMATION_TYPE,servicemanager.PYS_SERVICE_STARTED,(self._svc_name_, ''))

        from waptserver import app
        port = 8080
    #    ssl_a = cheroot.ssllib.ssl_builtin.BuiltinSSLAdapter(cert, cert_priv)  ...  ssl_adapter=ssl_a)
        wsgi_d = cheroot.wsgi.WSGIPathInfoDispatcher({'/': app})
        self.server = cheroot.wsgi.WSGIServer(('0.0.0.0', port), wsgi_app=wsgi_d)
        try:
            self.server.start()
        except KeyboardInterrupt:
            self.server.stop()


def ctrlHandler(ctrlType):
    return True

if __name__ == '__main__':
    win32api.SetConsoleCtrlHandler(ctrlHandler, True)
    win32serviceutil.HandleCommandLine(aservice)

