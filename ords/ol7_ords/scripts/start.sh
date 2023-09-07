function main {
  CONTAINER_VERSION="0.6.1"
  echo2 "******************************************************************************"
  echo2 "🔷 start.sh - ORDS/APEX container v. ${CONTAINER_VERSION}"

  if [ "$SYSDBA_DEPLOYMODE" = "true" ] && [ -n "$SYSDBA_USER" ] && [ -n "$SYSDBA_PASSWORD" ]; then
    echo2 "🔥 SYSDBA mode. APEX deployment, patching and app installation enabled!"
    CONNECTION_SYSDBA="${SYSDBA_USER}/${SYSDBA_PASSWORD}@//${DB_HOSTNAME}:${DB_PORT}/${DB_SERVICE} as sysdba"
    CONNECTION="${CONNECTION_SYSDBA}"
    SYSDBAMODE="true"
  else
    echo2 "▶️ Normal mode. App Installation only!"
    CONNECTION_APPS="${APP_SCHEMA}/${APP_SCHEMA_PASSWORD}@//${DB_HOSTNAME}:${DB_PORT}/${DB_SERVICE}"
    CONNECTION="${CONNECTION_APPS}"
    SYSDBAMODE="false"
  fi

  echo2 "******************************************************************************"
  export PATH=${PATH}:${JAVA_HOME}/bin

  # *************************************************************************************************
  # *************************************************************************************************
  # *************************************************************************************************

  echo "container: ${CONTAINER_VERSION}" > "${CATALINA_HOME}/webapps/ROOT/container_version.txt"

  FIRST_RUN="false"
  if [ ! -f ~/CONTAINER_ALREADY_STARTED_FLAG ]; then
    FIRST_RUN="true"
    touch ~/CONTAINER_ALREADY_STARTED_FLAG
  fi

  echo2 "Initializing sqlcl..."
  first_sqlcl_call

  echo2 "Check DB is available..."

  check_db
  while [ ${DB_OK} -eq 0 ]
  do
    echo2 "🔴 DB not available yet. Waiting for 30 seconds."
    sleep 30
    check_db
  done

  if [ ! -d ${CATALINA_BASE}/conf ]; then
    echo2 "******************************************************************************"
    echo2 "New CATALINA_BASE location."
    cp -r ${CATALINA_HOME}/conf ${CATALINA_BASE}
    cp -r ${CATALINA_HOME}/logs ${CATALINA_BASE}
    cp -r ${CATALINA_HOME}/temp ${CATALINA_BASE}
    cp -r ${CATALINA_HOME}/webapps ${CATALINA_BASE}
    cp -r ${CATALINA_HOME}/work ${CATALINA_BASE}
  fi

  if [ ! -d ${CATALINA_BASE}/webapps/i ]; then
    echo2 "******************************************************************************"
    echo2 "Extracting APEX images..."
    mkdir -p ${CATALINA_BASE}/webapps/i/
    cp -R ${SOFTWARE_DIR}/apex/images/* ${CATALINA_BASE}/webapps/i/
    #ln -s ${SOFTWARE_DIR}/apex/images ${CATALINA_BASE}/webapps/i
    APEX_IMAGES_REFRESH="false"

    if [ -d ${SOFTWARE_DIR}/apex/patch/*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9] ]; then
      echo2 "Adding/overwriting APEX images from patch..."
      cp -R ${SOFTWARE_DIR}/apex/patch/*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]/images/* ${CATALINA_BASE}/webapps/i/
    fi
  fi

  if [ "${APEX_IMAGES_REFRESH}" == "true" ]; then
    echo2 "******************************************************************************"
    echo2 "Overwrite APEX images..."
    cp -R ${SOFTWARE_DIR}/apex/images/* ${CATALINA_BASE}/webapps/i/

    if [ -d ${SOFTWARE_DIR}/apex/patch/*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9] ]; then
      echo2 "Overwrite APEX images from patch..."
      cp -R ${SOFTWARE_DIR}/apex/patch/*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]/images/* ${CATALINA_BASE}/webapps/i/
    fi
  fi

  cd ${SQL_DIR}

  if [ "$SYSDBAMODE" == "true" ]; then

    install_dba_configure

    dba_create_apex_tablespaces ${APP_SCHEMA} ${APEX_TABLESPACE} ${APEX_TABLESPACE_FILES}

    if [ "${FIRST_RUN}" == "true" ]; then

      check_apex

      if [ ${APEX_OK} -eq 0 ]; then
        install_apex
      fi
    fi
  fi

  echo2 "******************************************************************************"
  echo2 "Configuring ORDS..."
  cd ${ORDS_HOME}

  export ORDS_CONFIG=${ORDS_CONF}

  ${ORDS_HOME}/bin/ords --config ${ORDS_CONF} install \
       --log-folder ${ORDS_CONF}/logs \
       --admin-user "${SYSDBA_USER} as SYSDBA" \
       --db-hostname ${DB_HOSTNAME} \
       --db-port ${DB_PORT} \
       --db-servicename ${DB_SERVICE} \
       --feature-db-api true \
       --feature-rest-enabled-sql true \
       --feature-sdw true \
       --gateway-mode proxied \
       --gateway-user APEX_PUBLIC_USER \
       --proxy-user \
       --password-stdin <<EOF
  ${SYSDBA_PASSWORD}
  ${APEX_LISTENER_PASSWORD}
EOF

  cp ords.war ${CATALINA_BASE}/webapps/${CONTEXT_ROOT}.war

  cd ${SQL_DIR}


  if [ "$SYSDBAMODE" == "true" ]; then
    dba_configure ${APP_WORKSPACE} ${APP_SCHEMA} ${DB_ROOTPATH} ${SMTP_HOST} ${SMTP_PORT} ${ORDS_PATH}
  fi

  install_app ${APP_WORKSPACE} ${APP_SCHEMA} ${APP1_ID} ${APP1_ALIAS} ${APP1_FILENAME} ${APP1_VERSION}
  install_app ${APP_WORKSPACE} ${APP_SCHEMA} ${APP2_ID} ${APP2_ALIAS} ${APP2_FILENAME} ${APP2_VERSION}

  #else
  #  check_app ${APP_WORKSPACE} ${APP_SCHEMA} ${APP1_ID} ${APP1_ALIAS} ${APP1_FILENAME} ${APP1_VERSION}
  #  check_app ${APP_WORKSPACE} ${APP_SCHEMA} ${APP2_ID} ${APP2_ALIAS} ${APP2_FILENAME} ${APP2_VERSION}
  #fi

  recompile

  if [ ! -f ${KEYSTORE_DIR}/keystore.jks ]; then
    echo2 "******************************************************************************"
    echo2 "Configure HTTPS..."
    mkdir -p ${KEYSTORE_DIR}
    cd ${KEYSTORE_DIR}
    ${JAVA_HOME}/bin/keytool -genkey -keyalg RSA -alias selfsigned -keystore keystore.jks \
       -dname "CN=${HOSTNAME}, OU=My Department, O=My Company, L=Birmingham, ST=West Midlands, C=GB" \
       -storepass ${KEYSTORE_PASSWORD} -validity 3600 -keysize 2048 -keypass ${KEYSTORE_PASSWORD}

    sed -i -e "s|###KEYSTORE_DIR###|${KEYSTORE_DIR}|g" ${SCRIPTS_DIR}/server.xml
    sed -i -e "s|###KEYSTORE_PASSWORD###|${KEYSTORE_PASSWORD}|g" ${SCRIPTS_DIR}/server.xml
    sed -i -e "s|###AJP_SECRET###|${AJP_SECRET}|g" ${SCRIPTS_DIR}/server.xml
    sed -i -e "s|###AJP_ADDRESS###|${AJP_ADDRESS}|g" ${SCRIPTS_DIR}/server.xml
    sed -i -e "s|###PROXY_IPS###|${PROXY_IPS}|g" ${SCRIPTS_DIR}/server.xml
    cp ${SCRIPTS_DIR}/server.xml ${CATALINA_BASE}/conf
    cp ${SCRIPTS_DIR}/web.xml ${CATALINA_BASE}/conf
  fi;

  # configure extended Access Log
  valve_element='<Valve className="org.apache.catalina.valves.ExtendedAccessLogValve" directory="logs" fileDateFormat="" pattern="date time time-taken x-H(contentLength) x-H(protocol) sc-status cs-method cs-uri c-dns x-H(characterEncoding) bytes x-H(authType) x-H(secure) x-H(remoteUser) S x-H(requestedSessionId) x-H(SOAPAction)" prefix="extended_access" resolveHosts="true" suffix=".log"/>'

  # add Valve-element into server.xml
  sed -i "/<\/Host>/i \ \ $valve_element" "${CATALINA_BASE}/conf/server.xml"
  touch "${CATALINA_BASE}/logs/extended_access.log"

  echo2 "******************************************************************************"
  echo2 "🟢 Starting Tomcat..."
  ${CATALINA_HOME}/bin/startup.sh

  TOMCAT_STARTED="true"

  echo2 "******************************************************************************"
  echo2 "Tail the catalina.out file as a background process and wait on the process so script never ends..."
  tail -f ${CATALINA_BASE}/logs/catalina.out &
  tail -f ${CATALINA_BASE}/logs/extended_access.log &
  bgPID=$!
  wait $bgPID
}



function echo2 {
  PAR=$1
  echo "$(date): ${PAR}"
}

function gracefulshutdown {
  echo2 "🛑️ Received termination request."

  if [ -n "$TOMCAT_STARTED" ]; then
    echo2 "🛑️ Shutting down Tomcat..."
    ${CATALINA_HOME}/bin/shutdown.sh
  fi
}

trap gracefulshutdown SIGINT
trap gracefulshutdown SIGTERM
trap gracefulshutdown SIGKILL

function first_sqlcl_call {
  # wegen WARNING: Failed to save history
  RETVAL=$(/u01/sqlcl/bin/sql -S /NOLOG > /dev/null 2>&1 << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF TAB OFF
EOF
)
}

# *************************************************************************************************
function check_db {
#  CONNECTION=$1

  RETVAL=$(/u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 VERIFY OFF HEADING OFF TAB OFF
    conn ${CONNECTION}
    SELECT 'Connected to '||sys_context('USERENV','DB_NAME') as f FROM dual;
EOF

})

  RETVAL2="${RETVAL//[$'\t\r\n']}"

  if [[ "${RETVAL2}" == "Connected to "* ]]; then
    echo2 "🟢 ${RETVAL2}"
    DB_OK=1
  else
    error=$(echo "$RETVAL" | grep -oP 'Error Message = \K.*')
    if [ -n "$error" ]; then
      echo2 "🔴 $error"
    else
      ora=$(echo "$RETVAL" | grep -oP 'ORA-\K.*')
      if [ -n "$ora" ]; then
        echo2 "🔴 ORA-$ora"
      else
        echo2 "🔴 Unexpected connection error"
      fi
    fi

    DB_OK=0
  fi
}


# *************************************************************************************************
function install_dba_configure {
#  CONNECTION=$1

  echo2 "******************************************************************************"
  echo2 "Installing procedure DBA_CONFIGURE..."

  /u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF TAB OFF
    conn ${CONNECTION_SYSDBA}
    alter session set current_schema = ANONYMOUS;
    @DBA_CONFIGURE.sql
EOF
}

# *************************************************************************************************
function check_apex {
#  CONNECTION=$1

  RETVAL=$(/u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF TAB OFF
    conn ${CONNECTION_SYSDBA}
    whenever sqlerror exit sql.sqlcode
    select nvl(max(decode(COMP_ID, 'APEX', status || ' ' || version || ' ' || schema, '')), '0.0.0 NOT_INSTALLED')
    from   dba_registry
    ;
EOF
)

  RETVAL="${RETVAL//[$'\t\r\n']}"
  echo2 "Detected APEX Version: ${RETVAL}, expecting ${APEX_MIN_VERSION}"

  if [ "$RETVAL" = "VALID $APEX_MIN_VERSION" ]; then
    APEX_OK=1
    echo2 "✅ OK"
  else
    APEX_OK=0
    echo2 "⚠️ APEX Installation/Upgrade needed"
  fi

  RETVAL1=$(/u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF TAB OFF
    conn ${CONNECTION_SYSDBA}
    whenever sqlerror exit sql.sqlcode
    alter user apex_public_user identified by "${APEX_PUBLIC_USER_PASSWORD}" account unlock;
EOF
)

}

# *************************************************************************************************
function install_apex {
  echo2 "******************************************************************************"
  echo2 "Installing APEX..."
  cd ${SOFTWARE_DIR}/apex

  /u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF TAB OFF ECHO OFF
    conn ${CONNECTION_SYSDBA}
    @apxsilentins.sql ${APEX_TABLESPACE} ${APEX_TABLESPACE_FILES} ${TEMP_TABLESPACE} ${APEX_STATIC_FILES_PATH} ${APEX_PUBLIC_USER_PASSWORD} ${APEX_LISTENER_PASSWORD} ${APEX_REST_PUBLIC_USER_PASSWORD} ${APEX_INTERNAL_ADMIN_PASSWORD}
EOF

#  echo2 "******************************************************************************"
#  echo2 "APEX REST Config..."
#
#  /u01/sqlcl/bin/sql -S /NOLOG << EOF
#    SET PAGESIZE 0 VERIFY OFF HEADING OFF TAB OFF
#    conn ${CONNECTION} as SYSDBA
#    whenever sqlerror exit sql.sqlcode
#    @apex_rest_config.sql ${APEX_LISTENER_PASSWORD} ${APEX_REST_PASSWORD}
#EOF

  cd ${SOFTWARE_DIR}/apex/patch/*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]/

  patchdir=$(basename "$(pwd)")
  echo2 "patchdir: ${patchdir}"

  if [ -f "${SOFTWARE_DIR}/apex/patch/${patchdir}/catpatch.sql" ]; then
    echo "💡 APEX patch found at ${patchdir}/catpatch.sql. Installing..."

    /u01/sqlcl/bin/sql -S /NOLOG << EOF
      SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF TAB OFF ECHO OFF
      conn ${CONNECTION_SYSDBA}
      @catpatch.sql
EOF

  else
    echo2 "⚠️ APEX patch not found. Skipping patch installation."
  fi

  cd ${SOFTWARE_DIR}

  echo2 "******************************************************************************"
  echo2 "Checking APEX after installation..."
  check_apex ${CONNECTION_SYSDBA}
}

function dba_create_apex_tablespaces {
  SCHEMA=$1
  APEX_TABLESPACE=$2
  APEX_TABLESPACE_FILES=$3

  echo2 "******************************************************************************"
  echo2 "Checking/creating APEX Tablespaces..."

  /u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF TAB OFF SERVEROUTPUT ON
    conn ${CONNECTION_SYSDBA}
    exec dbms_output.enable(null)
    begin ANONYMOUS."_DBA_CONFIGURE"
      ('${SCHEMA}',
       apexTablespace       => '${APEX_TABLESPACE}',
       apexTablespaceFiles  => '${APEX_TABLESPACE_FILES}',
       apexTablespaceOnly   => true,
       storageOptions       => '${APEX_TABLESPACE_STORAGE_OPTIONS}',
       runIt                => true
      );
    end;
    /
EOF

}

function dba_configure {
  WORKSPACE=$1
  SCHEMA=$2
  DB_ROOTPATH=$3
  SMTP_HOST=$4
  SMTP_PORT=$5
  ORDS_PATH=$6

  echo2 "******************************************************************************"
  echo2 "Configuring schema ${SCHEMA}..."

  /u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF TAB OFF SERVEROUTPUT ON
    conn ${CONNECTION_SYSDBA}
    exec dbms_output.enable(null)
    begin ANONYMOUS."_DBA_CONFIGURE"
      ('${SCHEMA}',
       smtpHost      => '${SMTP_HOST}',
       smtpPort      => '${SMTP_PORT}',
       ordsPath      => '${ORDS_PATH}',
       rootPath      => '${DB_ROOTPATH}',
       runIt         => true
      );
    end;
    /
EOF

  RETVAL=$(/u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF TAB OFF
    conn ${CONNECTION_SYSDBA}
    select nvl(max(OBJECT_NAME),'NOT_INSTALLED')
    from   ALL_OBJECTS
    where  OWNER = '${SCHEMA}' and OBJECT_NAME  = 'CCFLAGS'
    ;
EOF
)

  RETVAL="${RETVAL//[$'\t\r\n']}"

  if [[ "${RETVAL}" = "NOT_INSTALLED" ]]; then
  echo2 "Installing CCFLAGS package..."
  /u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF TAB OFF
    conn ${CONNECTION_SYSDBA}
    alter session set current_schema = ${SCHEMA};
    @CCFLAGS.sql
EOF
  fi

  echo2 "******************************************************************************"
  echo2 "Configuration of schema ${SCHEMA} finished."
}

function check_app {
#  CONNECTION=$1
  WORKSPACE=$1
  SCHEMA=$2
  APP_ID=$3
  APP_ALIAS=$4
  FILENAME=$5
  APP_MIN_VERSION=$6

  echo2 "******************************************************************************"
  echo2 "Checking app #${APP_ID}: ${APP_ALIAS} >= v. ${APP_MIN_VERSION} from ${FILENAME} in workspace/schema ${WORKSPACE}/${SCHEMA}"

  RETVAL=$(/u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF TAB OFF
    conn ${CONNECTION_APPS}
    select nvl(max(substr(version, 1, instr(version, ' '))
                   || case when availability_status like '%Available%' then 'AVAILABLE' else 'UNAVAILABLE' end),
               '0.0.0 NOT_INSTALLED'
              )
    from   APEX_APPLICATIONS
    where  WORKSPACE       = upper('${WORKSPACE}')
      and  ALIAS           = upper('${APP_ALIAS}')
      and  OWNER           = upper('${SCHEMA}')
      and  APPLICATION_ID  = '${APP_ID}'
    ;
EOF
)

  RETVAL="${RETVAL//[$'\t\r\n']}"
  if [[ "${RETVAL}" > "${APP_MIN_VERSION}" ]]; then
    if [[ "${RETVAL}" == *" AVAILABLE"* ]]; then
      APP_OK=1
      echo2 "✅ OK"
    else
      APP_OK=0
      echo2 "🔴️ unexpected app status: ${RETVAL}"
    fi
  else
    APP_OK=0
    echo2 "⚠️ found ${RETVAL} ...App Installation/Upgrade needed"
  fi

  echo "${WORKSPACE}.${APP_ALIAS}: ${RETVAL}" > "${CATALINA_BASE}/webapps/ROOT/${APP_ALIAS}_version.txt"
}


###############################################################################
function install_app {
  #CONNECTION=$1
  WORKSPACE=$1
  SCHEMA=$2
  APP_ID=$3
  APP_ALIAS=$4
  FILENAME=$5
  APP_MIN_VERSION=$6

  check_app $1 $2 $3 $4 $5 $6

  if [ ${APP_OK} -eq 0 ]; then

    cd ${SQL_DIR}

    /u01/sqlcl/bin/sql -S /NOLOG << EOF
      SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF TAB OFF
      conn ${CONNECTION_SYSDBA}
      alter session set current_schema = ${SCHEMA};
      exec apex_util.set_workspace('${WORKSPACE}')
      exec apex_application_install.set_workspace_id( apex_util.find_security_group_id( p_workspace => '${WORKSPACE}'))
      exec apex_application_install.set_schema('${SCHEMA}')
      exec apex_application_install.set_application_id('${APP_ID}')
      exec apex_application_install.set_application_alias('${APP_ALIAS}')
      exec apex_application_install.set_auto_install_sup_obj(true)
      exec apex_application_install.generate_offset

      @${FILENAME}
EOF

    echo2 "App #${APP_ID}: ${APP_ALIAS} installation completed"

    check_app $1 $2 $3 $4 $5 $6

  fi

}



function recompile {
#  CONNECTION=$1

  RETVAL=$(/u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF TAB OFF
    conn ${CONNECTION_APPS}
    alter session set current_schema = ${SCHEMA};
    select to_char(count(*)) from all_errors where owner = '${SCHEMA}'
    ;
EOF
)

  RETVAL="${RETVAL//[$'\t\r\n']}"

  echo2 "******************************************************************************"

  if [[ "${RETVAL}" > "0" ]]; then
    echo2 "⚠️ Schema ${SCHEMA} has ${RETVAL} compilation errors! Compiling..."

    /u01/sqlcl/bin/sql -S /NOLOG << EOF
      SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF LINESIZE 1000
      conn ${CONNECTION_APPS}
      alter session set current_schema = ${SCHEMA};
      exec DBMS_UTILITY.compile_schema(SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'))
      Select rpad(replace(UER.type,' ', '_')||' '||UER.name||' (' || (UER.line) || ')', 40)||UER.text as err
      From   user_errors UER
      ;
EOF

    RETVAL=$(/u01/sqlcl/bin/sql -S /NOLOG << EOF
      SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF TAB OFF
      conn ${CONNECTION_APPS}
      select to_char(count(*)) from all_errors where owner = '${SCHEMA}'
      ;
EOF
)
    echo2 "******************************************************************************"
  fi

  RETVAL="${RETVAL//[$'\t\r\n']}"
  if [[ "${RETVAL}" > "0" ]]; then
    echo2 "🔴 Still ${RETVAL} Compilation error(s)"
  else
    echo2 "✅ No compilation errors!"
  fi
}


# **************************************************************************************
main

