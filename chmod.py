#-------------------------------------------------------------------------------
# Name:        module1
# Purpose:
#
# Author:      htouvet
#
# Created:     17/07/2013
# Copyright:   (c) htouvet 2013
# Licence:     <your licence>
#-------------------------------------------------------------------------------

from winsys import security
with security.security ("c:/wapt") as s:
    s.dacl = [ ('Administrators', "F", "ALLOW"),('Everyone','R','ALLOW')]
    s.break_inheritance(False)
