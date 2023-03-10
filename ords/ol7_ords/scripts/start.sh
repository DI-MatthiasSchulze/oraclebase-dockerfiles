echo "******************************************************************************"
echo "$(date) Check if this is the first run."
echo "******************************************************************************"
FIRST_RUN="false"
if [ ! -f ~/CONTAINER_ALREADY_STARTED_FLAG ]; then
  echo "First run."
  FIRST_RUN="true"
  touch ~/CONTAINER_ALREADY_STARTED_FLAG
else
  echo "Not first run."
fi

echo "******************************************************************************"
echo "$(date) Handle shutdowns."
echo "$(date) docker stop --time=30 {container}"
echo "******************************************************************************"
function gracefulshutdown {
  ${CATALINA_HOME}/bin/shutdown.sh
}

trap gracefulshutdown SIGINT
trap gracefulshutdown SIGTERM
trap gracefulshutdown SIGKILL

echo "******************************************************************************"
echo "$(date) Check DB is available."
echo "******************************************************************************"
export PATH=${PATH}:${JAVA_HOME}/bin

function check_db {
  CONNECTION=$1
  echo "checking db... ${CONNECTION}"

  RETVAL=$(/u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF TAB OFF
    conn ${CONNECTION} as SYSDBA
    whenever sqlerror exit sql.sqlcode
    SELECT 'Alive' FROM dual;
EOF
)

  echo "${RETVAL}"

  RETVAL="${RETVAL//[$'\t\r\n']}"
  if [ "${RETVAL}" = "Alive" ]; then
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
    select nvl(max(version || ' ' || schema || ' ' || status), '0.0.0 NOT_INSTALLED')
    from   dba_registry
    where  COMP_ID = 'APEX'
    group by schema, version, status
    ;
EOF
)

  RETVAL="${RETVAL//[$'\t\r\n']}"
  echo "Detected APEX Version: ${RETVAL}, expecting >= ${APEX_MIN_VERSION}"

  AMV="${APEX_MIN_VERSION}"
  VALID='VALID'

  if [[ "${RETVAL}" > "${AMV}" ]]; then
    if [[ "${RETVAL}" == *"$VALID"* ]]; then
      APEX_OK=1
      echo "...OK"
    else
      APEX_OK=0
      echo "...APEX is not VALID"
    fi
  else
    APEX_OK=0
    echo "...APEX Installation/Upgrade needed"
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

  echo "******************************************************************************"
  echo "Installing APEX..."
  echo "******************************************************************************"
  cd ${SOFTWARE_DIR}/apex

  /u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF TAB OFF
    conn ${CONNECTION} as SYSDBA
    @apexins.sql SYSAUX SYSAUX TEMP /i/
EOF

  echo "******************************************************************************"
  echo "APEX INSTALL RESULT:"
  echo "${RETVAL}"

  echo "******************************************************************************"
  echo "Create APEX Admin user..."
  echo "******************************************************************************"

  /u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 VERIFY OFF HEADING OFF TAB OFF
    conn ${CONNECTION} as SYSDBA
    whenever sqlerror exit sql.sqlcode
    BEGIN
      APEX_UTIL.set_security_group_id( 10 );

      APEX_UTIL.create_user(
          p_user_name       => 'ADMIN',
          p_email_address   => 'me@example.com',
          p_web_password    => 'oracle',
          p_developer_privs => 'ADMIN' );

      APEX_UTIL.set_security_group_id( null );
      COMMIT;
    END;
    /
EOF

  echo "******************************************************************************"
  echo "APEX REST Config..."

  /u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 VERIFY OFF HEADING OFF TAB OFF
    conn ${CONNECTION} as SYSDBA
    whenever sqlerror exit sql.sqlcode
    @apex_rest_config.sql ${APEX_LISTENER_PASSWORD} ${APEX_REST_PASSWORD}
EOF

  echo "******************************************************************************"
  echo "Checking APEX after installation..."
  check_apex ${CONNECTION}

}

function dba_configure {
  CONNECTION=$1
  WORKSPACE=$2
  SCHEMA=$3
  DB_ROOTPATH=$4
  SMTP_HOST=$5
  SMTP_PORT=$6

  echo "******************************************************************************"
  echo "Configuring schema ${SCHEMA}..."

  /u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 VERIFY OFF HEADING OFF TAB OFF
    conn ${CONNECTION} as SYSDBA
    @DBA_CONFIGURE.sql
EOF

  /u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 VERIFY OFF HEADING OFF TAB OFF SERVEROUTPUT ON
    conn ${CONNECTION} as SYSDBA
    exec dbms_output.enable(null)
    begin dba_configure
      ('${SCHEMA}',
       optionFiletransfer  => true,
       rootPath            => '${DB_ROOTPATH}/${SCHEMA}',
       smtpHost            => '${SMTP_HOST}',
       smtpPort            => '${SMTP_PORT}',
       runIt               => true
      );
    end;
    /
EOF

  echo "******************************************************************************"
  echo "configuration of schema ${SCHEMA} finished"
  echo "******************************************************************************"
}


function install_app {
  CONNECTION=$1
  WORKSPACE=$2
  SCHEMA=$3
  APP_ID=$4
  APP_ALIAS=$5
  FILENAME=$6
  APP_MIN_VERSION=$7

  echo "******************************************************************************"
  echo "Checking app #${APP_ID}: ${APP_ALIAS} >= v. ${APP_MIN_VERSION} from ${FILENAME} @${CONNECTION}"

  RETVAL=$(/u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF TAB OFF
    conn ${CONNECTION}
    select nvl(max(substr(version, 1, instr(version, ' '))
                   || case when availability_status like '%Available%' then 'AVAILABLE' else 'UNAVAILABLE' end),
               '0.0.0 NOT_INSTALLED'
              )
    from   APEX_APPLICATIONS
    where  WORKSPACE       = '${WORKSPACE}'
      and  APPLICATION_ID  = '${APP_ID}'
      and  ALIAS           = '${APP_ALIAS}'
      and  OWNER           = '${SCHEMA}'
    group by version, availability_status
    ;
EOF
)

  RETVAL="${RETVAL//[$'\t\r\n']}"
  echo "${RETVAL}"

  if [[ "${RETVAL}" > "${AMV}" ]]; then
    if [[ "${RETVAL}" == *" AVAILABLE"* ]]; then
      APP_OK=1
      echo "...OK"
    else
      APP_OK=0
      echo "...APP is UNAVAILABLE"
    fi
  else
    APP_OK=0
    echo "${RETVAL} ...App Installation/Upgrade needed"
  fi

  if [ ${APP_OK} -eq 0 ]; then

    /u01/sqlcl/bin/sql -S /NOLOG << EOF
      SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF TAB OFF
      conn ${CONNECTION}
      exec apex_util.set_workspace('${WORKSPACE}')
      exec apex_application_install.set_workspace_id( apex_util.find_security_group_id( p_workspace => '${WORKSPACE}'))
      exec apex_application_install.set_schema('${SCHEMA}')
      exec apex_application_install.set_application_id('${APP_ID}')
      exec apex_application_install.set_application_alias('${APP_ALIAS}')
      exec apex_application_install.set_auto_install_sup_obj(true)
      exec apex_application_install.generate_offset

      @${FILENAME}
EOF

  fi

  echo "******************************************************************************"
  echo "app #${APP_ID}: ${APP_ALIAS} installed"

}




CONNECTION="${SYSDBA_USER}/${SYSDBA_PASSWORD}@//${DB_HOSTNAME}:${DB_PORT}/${DB_SERVICE}"

check_db ${CONNECTION}
while [ ${DB_OK} -eq 1 ]
do
  echo "DB not available yet. Waiting for 30 seconds."
  sleep 30
  check_db ${CONNECTION}
done


if [ ! -d ${CATALINA_BASE}/conf ]; then
  echo "******************************************************************************"
  echo "$(date) New CATALINA_BASE location."
  echo "******************************************************************************"
  cp -r ${CATALINA_HOME}/conf ${CATALINA_BASE}
  cp -r ${CATALINA_HOME}/logs ${CATALINA_BASE}
  cp -r ${CATALINA_HOME}/temp ${CATALINA_BASE}
  cp -r ${CATALINA_HOME}/webapps ${CATALINA_BASE}
  cp -r ${CATALINA_HOME}/work ${CATALINA_BASE}
fi

if [ ! -d ${CATALINA_BASE}/webapps/i ]; then
  echo "******************************************************************************"
  echo "$(date) First time APEX images."
  echo "******************************************************************************"
  mkdir -p ${CATALINA_BASE}/webapps/i/
  # cp -R ${SOFTWARE_DIR}/apex/images/* ${CATALINA_BASE}/webapps/i/
  ln -s ${SOFTWARE_DIR}/apex/images ${CATALINA_BASE}/webapps/i
  APEX_IMAGES_REFRESH="false"
fi

if [ "${APEX_IMAGES_REFRESH}" == "true" ]; then
  echo "******************************************************************************"
  echo "$(date) Overwrite APEX images."
  echo "******************************************************************************"
  cp -R ${SOFTWARE_DIR}/apex/images/* ${CATALINA_BASE}/webapps/i/
fi

if [ "${FIRST_RUN}" == "true" ]; then

  check_apex ${CONNECTION}

  if [ ${APEX_OK} -eq 0 ]; then
    install_apex ${CONNECTION}
  fi

  echo "******************************************************************************"
  echo "$(date) Configure ORDS. Safe to run on DB with existing config."
  echo "******************************************************************************"
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


echo "******************************************************************************"
echo "$(date) Installing Apps..."
echo "******************************************************************************"

export WORKSPACE="INTRACK"
export SCHEMA="INTRACK"

cd ${SOFTWARE_DIR}
dba_configure ${CONNECTION} ${WORKSPACE} ${SCHEMA} ${DB_ROOTPATH} ${SMTP_HOST} ${SMTP_HOST}

CONNECTION="${SCHEMA}/oracle@//${DB_HOSTNAME}:${DB_PORT}/${DB_SERVICE}"

install_app ${CONNECTION} ${WORKSPACE} ${SCHEMA} "1001" "intrack"   "intrack_21_2.sql" "2.9"
install_app ${CONNECTION} ${WORKSPACE} ${SCHEMA} "1002" "dashboard" "dashb_22_1.sql"   "1.9"


if [ ! -f ${KEYSTORE_DIR}/keystore.jks ]; then
  echo "******************************************************************************"
  echo "$(date) Configure HTTPS."
  echo "******************************************************************************"
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

echo "******************************************************************************"
echo "$(date) Start Tomcat."
echo "******************************************************************************"
${CATALINA_HOME}/bin/startup.sh

echo "******************************************************************************"
echo "$(date) Tail the catalina.out file as a background process"
echo "$(date) and wait on the process so script never ends."
echo "******************************************************************************"
tail -f ${CATALINA_BASE}/logs/catalina.out &
bgPID=$!
wait $bgPID
