function echo2 {
  PAR=$1
  echo "$(date): ${PAR}"
}

echo2 "******************************************************************************"
echo2 "🔷 start.sh - ORDS/APEX container v. 0.0.1 \$Revision: 1 $"

FIRST_RUN="false"
if [ ! -f ~/CONTAINER_ALREADY_STARTED_FLAG ]; then
  #echo2 "First run."
  FIRST_RUN="true"
  touch ~/CONTAINER_ALREADY_STARTED_FLAG
#else
  #echo2 "Not first run."
fi

echo2 "******************************************************************************"
echo2 "Handle shutdowns."
echo2 "docker stop --time=30 {container}"
function gracefulshutdown {
  ${CATALINA_HOME}/bin/shutdown.sh
}

trap gracefulshutdown SIGINT
trap gracefulshutdown SIGTERM
trap gracefulshutdown SIGKILL

echo2 "******************************************************************************"
echo2 "Check DB is available..."
export PATH=${PATH}:${JAVA_HOME}/bin

function first_sqlcl_call {
  # wegen WARNING: Failed to save history
  CONNECTION=$1

  RETVAL=$(/u01/sqlcl/bin/sql -S /NOLOG > /dev/null 2>&1 << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF TAB OFF
    conn ${CONNECTION} as SYSDBA
    whenever sqlerror exit sql.sqlcode
    SELECT 'Alive' FROM dual;
EOF
)
}

function check_db {
  CONNECTION=$1
  #echo "checking db... ${CONNECTION}"

  RETVAL=$(/u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF TAB OFF
    conn ${CONNECTION} as SYSDBA
    SELECT 'Connected to '||sys_context('USERENV','DB_NAME')||': '|| banner as f FROM V\$Version;
EOF
)

  RETVAL="${RETVAL//[$'\t\r\n']}"
  echo2 "${RETVAL}"

  if [[ "${RETVAL}" == "Connected to"* ]]; then
    DB_OK=0
  else
    DB_OK=1
  fi
}

function check_apex {
  CONNECTION=$1

  RETVAL=$(/u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF TAB OFF
    conn ${CONNECTION} as SYSDBA
    whenever sqlerror exit sql.sqlcode
    select nvl(max(decode(COMP_ID, 'APEX', version || ' ' || schema || ' ' || status, '')), '0.0.0 NOT_INSTALLED')
    from   dba_registry
    ;
EOF
)

  RETVAL="${RETVAL//[$'\t\r\n']}"
  echo2 "Detected APEX Version: ${RETVAL}, expecting >= ${APEX_MIN_VERSION}"

  AMV="${APEX_MIN_VERSION}"
  VALID='VALID'

  if [[ "${RETVAL}" > "${AMV}" ]]; then
    if [[ "${RETVAL}" == *"$VALID"* ]]; then
      APEX_OK=1
      echo2 "...OK"
    else
      APEX_OK=0
      echo2 "...APEX is not VALID"
    fi
  else
    APEX_OK=0
    echo2 "...APEX Installation/Upgrade needed"
  fi

  RETVAL1=$(/u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF TAB OFF
    conn ${CONNECTION} as SYSDBA
    whenever sqlerror exit sql.sqlcode
    alter user apex_public_user identified by "${APEX_PUBLIC_USER_PASSWORD}" account unlock;
EOF
)

}


function install_apex {
  CONNECTION=$1

  echo2 "******************************************************************************"
  echo2 "Installing APEX..."
  cd ${SOFTWARE_DIR}/apex

  /u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF TAB OFF
    conn ${CONNECTION} as SYSDBA
    @apexins.sql SYSAUX SYSAUX TEMP /i/
EOF

  echo2 "******************************************************************************"
  echo2 "APEX INSTALL RESULT:"
  echo2 "${RETVAL}"

  echo2 "******************************************************************************"
  echo2 "APEX REST Config..."

  /u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 VERIFY OFF HEADING OFF TAB OFF
    conn ${CONNECTION} as SYSDBA
    whenever sqlerror exit sql.sqlcode
    @apex_rest_config.sql ${APEX_LISTENER_PASSWORD} ${APEX_REST_PASSWORD}
EOF

  echo2 "******************************************************************************"
  echo2 "Checking APEX after installation..."
  check_apex ${CONNECTION}

}

function dba_configure {
  CONNECTION=$1
  WORKSPACE=$2
  SCHEMA=$3
  DB_ROOTPATH=$4
  SMTP_HOST=$5
  SMTP_PORT=$6
  ORDS_PATH=$7

  echo2 "******************************************************************************"
  echo2 "Configuring schema ${SCHEMA}..."

  /u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF TAB OFF
    conn ${CONNECTION} as SYSDBA
    @DBA_CONFIGURE.sql
EOF

  /u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF TAB OFF SERVEROUTPUT ON
    conn ${CONNECTION} as SYSDBA
    exec dbms_output.enable(null)
    begin dba_configure
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
    conn ${CONNECTION} as SYSDBA
    select nvl(max(OBJECT_NAME),'NOT_INSTALLED')
    from   ALL_OBJECTS
    where  OWNER = '${SCHEMA}' and OBJECT_NAME  = 'CCFLAGS'
    ;
EOF
)

  RETVAL="${RETVAL//[$'\t\r\n']}"

  echo2 "CCFLAGS: ${RETVAL}"

  if [[ "${RETVAL}" = "NOT_INSTALLED" ]]; then
  echo2 "Installing CCFLAGS package..."
  /u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF TAB OFF
    conn ${CONNECTION} as SYSDBA
    alter session set current_schema = ${SCHEMA};
    @CCFLAGS.sql
EOF
  fi

  echo2 "******************************************************************************"
  echo2 "Configuration of schema ${SCHEMA} finished."
}

function check_app {
  CONNECTION=$1
  WORKSPACE=$2
  SCHEMA=$3
  APP_ID=$4
  APP_ALIAS=$5
  FILENAME=$6
  APP_MIN_VERSION=$7

  echo2 "******************************************************************************"
  echo2 "Checking app #${APP_ID}: ${APP_ALIAS} >= v. ${APP_MIN_VERSION} from ${FILENAME} in workspace/schema ${WORKSPACE}/${SCHEMA}"

  RETVAL=$(/u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF TAB OFF
    conn ${CONNECTION} as SYSDBA
    select nvl(max(substr(version, 1, instr(version, ' '))
                   || case when availability_status like '%Available%' then 'AVAILABLE' else 'UNAVAILABLE' end),
               '0.0.0 NOT_INSTALLED'
              )
    from   APEX_APPLICATIONS
    where  WORKSPACE       = upper('${WORKSPACE}')
      and  ALIAS           = upper('${APP_ALIAS}')
      and  OWNER           = upper('${SCHEMA}')
      and  APPLICATION_ID  = '${APP_ID}'
    group by version, availability_status
    ;
EOF
)

  RETVAL="${RETVAL//[$'\t\r\n']}"
  if [[ "${RETVAL}" > "${APP_MIN_VERSION}" ]]; then
    if [[ "${RETVAL}" == *" AVAILABLE"* ]]; then
      APP_OK=1
      echo2 "...OK"
    else
      APP_OK=0
      echo2 "...unexpected app status: ${RETVAL}"
    fi
  else
    APP_OK=0
    echo2 "found ${RETVAL} ...App Installation/Upgrade needed"
  fi
}




###############################################################################
function install_app {
  #CONNECTION=$1
  #WORKSPACE=$2
  #SCHEMA=$3
  #APP_ID=$4
  #APP_ALIAS=$5
  #FILENAME=$6
  #APP_MIN_VERSION=$7

  check_app $1 $2 $3 $4 $5 $6 $7

  if [ ${APP_OK} -eq 0 ]; then

    /u01/sqlcl/bin/sql -S /NOLOG << EOF
      SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF TAB OFF
      conn ${CONNECTION} as SYSDBA
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
    #check_app $1 $2 $3 $4 $5 $6 $7
  fi

}



function recompile {
  CONNECTION=$1

  RETVAL=$(/u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF TAB OFF
    conn ${CONNECTION} as SYSDBA
    alter session set current_schema = ${SCHEMA};
    select to_char(count(*)) from all_errors where owner = '${SCHEMA}'
    ;
EOF
)

  RETVAL="${RETVAL//[$'\t\r\n']}"

  echo2 "******************************************************************************"

  if [[ "${RETVAL}" > "0" ]]; then
    echo2 "Schema ${SCHEMA} has ${RETVAL} compilation errors! Compiling..."

    /u01/sqlcl/bin/sql -S /NOLOG << EOF
      SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF LINESIZE 1000
      conn ${CONNECTION} as SYSDBA
      alter session set current_schema = ${SCHEMA};
      exec DBMS_UTILITY.compile_schema(SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'))
      Select rpad(replace(UER.type,' ', '_')||' '||UER.name||' (' || (UER.line) || ')', 40)||UER.text as err
      From   user_errors UER
      ;
EOF

    RETVAL=$(/u01/sqlcl/bin/sql -S /NOLOG << EOF
      SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF TAB OFF
      conn ${CONNECTION} as SYSDBA
      select to_char(count(*)) from all_errors where owner = '${SCHEMA}'
      ;
EOF
)
    echo2 "******************************************************************************"
  fi

  RETVAL="${RETVAL//[$'\t\r\n']}"
  if [[ "${RETVAL}" > "0" ]]; then
    echo2 "😱 Still ${RETVAL} Compilation error(s)"
  else
    echo2 "✅ No compilation errors!"
  fi
}

# **************************************************************************************
# main()

CONNECTION="${SYSDBA_USER}/${SYSDBA_PASSWORD}@//${DB_HOSTNAME}:${DB_PORT}/${DB_SERVICE}"

first_sqlcl_call ${CONNECTION}

check_db ${CONNECTION}
while [ ${DB_OK} -eq 1 ]
do
  echo2 "DB not available yet. Waiting for 30 seconds."
  sleep 30
  check_db ${CONNECTION}
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
fi

if [ "${APEX_IMAGES_REFRESH}" == "true" ]; then
  echo2 "******************************************************************************"
  echo2 "Overwrite APEX images..."
  cp -R ${SOFTWARE_DIR}/apex/images/* ${CATALINA_BASE}/webapps/i/
fi

if [ "${FIRST_RUN}" == "true" ]; then

  check_apex ${CONNECTION}

  if [ ${APEX_OK} -eq 0 ]; then
    install_apex ${CONNECTION}
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

fi

cd ${SOFTWARE_DIR}/db

dba_configure ${CONNECTION} ${APP_WORKSPACE} ${APP_SCHEMA} ${DB_ROOTPATH} ${SMTP_HOST} ${SMTP_PORT} ${ORDS_PATH}

install_app ${CONNECTION} ${APP_WORKSPACE} ${APP_SCHEMA} ${APP1_ID} ${APP1_ALIAS} ${APP1_FILENAME} ${APP1_VERSION}
install_app ${CONNECTION} ${APP_WORKSPACE} ${APP_SCHEMA} ${APP2_ID} ${APP2_ALIAS} ${APP2_FILENAME} ${APP2_VERSION}

recompile   ${CONNECTION}


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

echo2 "******************************************************************************"
echo2 "Starting Tomcat..."
${CATALINA_HOME}/bin/startup.sh

echo2 "******************************************************************************"
echo2 "Tail the catalina.out file as a background process and wait on the process so script never ends..."
tail -f ${CATALINA_BASE}/logs/catalina.out &
bgPID=$!
wait $bgPID
