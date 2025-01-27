# ------------------------------------------------------------------------------
# Dockerfile to build basic Oracle REST Data Services (ORDS) images
# Based on the following:
#   - Oracle Linux 7 - Slim
#   - Java 11 :
#       https://adoptium.net/releases.html?variant=openjdk11&jvmVariant=hotspot
#   - Tomcat 9.0.x :
#       https://tomcat.apache.org/download-90.cgi
#   - Oracle REST Data Services (ORDS) :
#       http://www.oracle.com/technetwork/developer-tools/rest-data-services/downloads/index.html
#   - Oracle Application Express (APEX) :
#       http://www.oracle.com/technetwork/developer-tools/apex/downloads/index.html
#   - Oracle SQLcl :
#       http://www.oracle.com/technetwork/developer-tools/sqlcl/downloads/index.html
#
# Example build and run. Assumes Docker network called "my_network" to connect to DB.
#
# docker build -t ol7_ords:latest .
# docker build --squash -t ol7_ords:latest .
# Podman
# docker build --format docker --no-cache -t ol8_ords:latest .
#
# docker run -dit --name ol7_ords_con -p 8080:8080 -p 8443:8443 --network=my_network -e DB_HOSTNAME=ol7_183_con ol7_ords:latest
# Pure CATALINA_BASE on a persistent volume.
# docker run -dit --name ol7_ords_con -p 8080:8080 -p 8443:8443 --network=my_network -e DB_HOSTNAME=ol7_183_con -v /home/docker_user/volumes/ol7_183_ords_tomcat:/u01/config/instance1 ol7_ords:latest
#
# docker logs --follow ol7_ords_con
# docker exec -it ol7_ords_con bash
#
# docker stop --time=30 ol7_ords_con
# docker start ol7_ords_con
#
# docker rm -vf ol7_ords_con
#
# ------------------------------------------------------------------------------

# Set the base image to Oracle Linux 7 - Slim
FROM oraclelinux:7-slim

# File Author / Maintainer
LABEL maintainer="info@dresden-informatik.de"

# ------------------------------------------------------------------------------
# Define fixed (build time) environment variables.
ENV JDK_AARCH64="OpenJDK11U-jdk_aarch64_linux_hotspot_11.0.18_10.tar.gz"       \
    JDK_X64="OpenJDK11U-jdk_x64_linux_hotspot_11.0.9_11.tar.gz"                \
    TOMCAT_SOFTWARE="apache-tomcat-9.0.71.tar.gz"                              \
    ORDS_SOFTWARE="ords-latest.zip"                                            \
    APEX_SOFTWARE="apex-latest.zip"                                            \
    SQLCL_SOFTWARE="sqlcl-latest.zip"                                          \
    APEX_SOFTWARE_PATCH="p34628174_2220_Generic.zip"                           \
    SOFTWARE_DIR="/u01/software"                                               \
    SCRIPTS_DIR="/u01/scripts"                                                 \
    SQL_DIR="/u01/sql"                                                         \
    KEYSTORE_DIR="/u01/keystore"                                               \
    ORDS_HOME="/u01/ords"                                                      \
    ORDS_CONF="/u01/config/ords"                                               \
    JAVA_HOME="/u01/java/latest"                                               \
    CATALINA_HOME="/u01/tomcat/latest"                                         \
    CATALINA_BASE="/u01/config/instance1"

# ------------------------------------------------------------------------------
# Define config (runtime) environment variables.
ENV DB_HOSTNAME="localhost"                                                    \
    DB_PORT="1521"                                                             \
    DB_SERVICE="xepdb1"                                                        \
    APEX_MIN_VERSION="22.2.10"                                                 \
    CONTEXT_ROOT="ords"                                                        \
    APP_WORKSPACE="APPS"                                                       \
    APP_SCHEMA="APPS"                                                          \
    APP_SCHEMA_PASSWORD="oracle"                                               \
    ORDS_PATH="apps"                                                           \
    APP1_ID="1001"                                                             \
    APP1_ALIAS="app1"                                                          \
    APP1_FILENAME="app1.sql"                                                   \
    APP1_VERSION="1.0.0"                                                       \
    APP2_ID=""                                                                 \
    APP2_ALIAS=""                                                              \
    APP2_FILENAME=""                                                           \
    APP2_VERSION=""                                                            \
    APEX_TABLESPACE="APEX"                                                     \
    APEX_TABLESPACE_FILES="APEX"                                               \
    APEX_PUBLIC_USER_PASSWORD="oracle"                                         \
    APEX_LISTENER_PASSWORD="oracle"                                            \
    APEX_REST_PUBLIC_USER_PASSWORD="oracle"                                    \
    APEX_INTERNAL_ADMIN_PASSWORD="Gehe1m!"                                     \
    APEX_STATIC_FILES_PATH="/i/"                                               \
    SYSDBA_DEPLOYMODE="true"                                                          \
    SYSDBA_USER="SYS"                                                          \
    SYSDBA_PASSWORD=""                                                         \
    DB_ROOTPATH="/opt/intrack"                                                 \
    SMTP_HOST="mail.smtp2go.com"                                               \
    SMTP_PORT="465"                                                            \
    KEYSTORE_PASSWORD="KeystorePassword1"                                      \
    TEMP_TABLESPACE="TEMP"                                                     \
    AJP_SECRET="AJPSecret1"                                                    \
    AJP_ADDRESS="::1"                                                          \
    APEX_IMAGES_REFRESH="false"                                                \
    APEX_TABLESPACE_STORAGE_OPTIONS=""                                         \
    PROXY_IPS="123.123.123.123\|123.123.123.124"                               \
    JAVA_OPTS="-Dconfig.url=${ORDS_CONF} -Xms1024M -Xmx1024M"

# ------------------------------------------------------------------------------
# Get all the files for the build.
COPY software/ ${SOFTWARE_DIR}/
COPY scripts/ ${SCRIPTS_DIR}/
COPY sql/ ${SQL_DIR}/

# ------------------------------------------------------------------------------
# Unpack all the software and remove the media.
# No config done in the build phase.
ARG TARGETPLATFORM
RUN if [ "$TARGETPLATFORM" = "linux/arm64" ]; then JDK=$JDK_AARCH64; else JDK=$JDK_X64; fi && \
    sh ${SCRIPTS_DIR}/install_os_packages.sh && \
    sh ${SCRIPTS_DIR}/ords_software_installation.sh ${JDK}

# Perform the following actions as the tomcat user
USER tomcat

#VOLUME [${CATALINA_BASE}]
EXPOSE 8080 8443
HEALTHCHECK --interval=1m --start-period=1m \
   CMD ${SCRIPTS_DIR}/healthcheck.sh >/dev/null || exit 1

# ------------------------------------------------------------------------------
# The start script performs all config based on runtime environment variables,
# and starts tomcat.
CMD exec ${SCRIPTS_DIR}/start.sh

# End
