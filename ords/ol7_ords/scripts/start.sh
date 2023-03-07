echo "******************************************************************************"
echo "Check if this is the first run." `date`
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
echo "Handle shutdowns." `date`
echo "docker stop --time=30 {container}" `date`
echo "******************************************************************************"
function gracefulshutdown {
  ${CATALINA_HOME}/bin/shutdown.sh
}

trap gracefulshutdown SIGINT
trap gracefulshutdown SIGTERM
trap gracefulshutdown SIGKILL

echo "******************************************************************************"
echo "Check DB is available." `date`
echo "******************************************************************************"
export PATH=${PATH}:${JAVA_HOME}/bin

function check_db {
  CONNECTION=$1
  echo "checking db..."

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
  echo "$ /u01/sqlcl/bin/sql -silent ${CONNECTION} as SYSDBA"

  RETVAL=$(/u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF TAB OFF
    conn ${CONNECTION} as SYSDBA
    whenever sqlerror exit sql.sqlcode
    select max(version || ' ' || schema || ' ' || status)
    from   dba_registry
    where  COMP_ID = 'APEX'
    group by schema, version, status
    ;
EOF
)

  AMV="${APEX_MIN_VERSION]}"

  echo "Found APEX Version: ${RETVAL}, expecting >= ${AMV}"

  if [ "${RETVAL}" -ge "$AMV" ]; then
    APEX_OK=1
    echo "...OK"
  else
    APEX_OK=0
    echo "...APEX Installation/Upgrade needed"
  fi
}


function install_apex {
  CONNECTION=$1

  echo "******************************************************************************"
  echo "Installing APEX..."
  echo "******************************************************************************"
  cd ${SOFTWARE_DIR}/apex

  RETVAL=$(/u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF TAB OFF
    conn ${CONNECTION} as SYSDBA
    whenever sqlerror exit sql.sqlcode
    @apexins.sql SYSAUX SYSAUX TEMP /i/
EOF
)

  echo "******************************************************************************"
  echo "APEX INSTALL RESULT:"
  echo "${RETVAL}"

  echo "******************************************************************************"
  echo "Create APEX Admin user..."
  echo "******************************************************************************"

  RETVAL2=$(/u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF TAB OFF
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
)

  echo "******************************************************************************"
  echo "CREATE USER RESULT:"
  echo "${RETVAL2}"

  echo "******************************************************************************"
  echo "APEX REST Config..."
  echo "******************************************************************************"

  RETVAL3=$(/u01/sqlcl/bin/sql -S /NOLOG << EOF
    SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF TAB OFF
    conn ${CONNECTION} as SYSDBA
    whenever sqlerror exit sql.sqlcode
    @apex_rest_config.sql ${APEX_LISTENER_PASSWORD} ${APEX_REST_PASSWORD}
EOF
)

  echo "******************************************************************************"
  echo "REST Config RESULT:"
  echo "${RETVAL3}"

  SUB='APEX successfully installed'

  if [[ "${RETVAL3}" == *"$SUB"* ]]; then
    APEX_INSTALLED_OK=0
  else
    APEX_INSTALLED_OK=1
  fi
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
  echo "New CATALINA_BASE location." `date`
  echo "******************************************************************************"
  cp -r ${CATALINA_HOME}/conf ${CATALINA_BASE}
  cp -r ${CATALINA_HOME}/logs ${CATALINA_BASE}
  cp -r ${CATALINA_HOME}/temp ${CATALINA_BASE}
  cp -r ${CATALINA_HOME}/webapps ${CATALINA_BASE}
  cp -r ${CATALINA_HOME}/work ${CATALINA_BASE}
fi

if [ ! -d ${CATALINA_BASE}/webapps/i ]; then
  echo "******************************************************************************"
  echo "First time APEX images." `date`
  echo "******************************************************************************"
  mkdir -p ${CATALINA_BASE}/webapps/i/
  cp -R ${SOFTWARE_DIR}/apex/images/* ${CATALINA_BASE}/webapps/i/
  APEX_IMAGES_REFRESH="false"
fi

if [ "${APEX_IMAGES_REFRESH}" == "true" ]; then
  echo "******************************************************************************"
  echo "Overwrite APEX images." `date`
  echo "******************************************************************************"
  cp -R ${SOFTWARE_DIR}/apex/images/* ${CATALINA_BASE}/webapps/i/
fi

if [ "${FIRST_RUN}" == "true" ]; then
  echo "******************************************************************************"
  echo "Configure ORDS. Safe to run on DB with existing config." `date`
  echo "******************************************************************************"
  cd ${ORDS_HOME}

  export ORDS_CONFIG=${ORDS_CONF}

  ${ORDS_HOME}/bin/ords --config ${ORDS_CONF} install \
       --log-folder ${ORDS_CONF}/logs \
       --admin-user ${SYSDBA_USER} \
       --db-hostname ${DB_HOSTNAME} \
       --db-port ${DB_PORT} \
       --db-servicename ${DB_SERVICE} \
       --feature-db-api true \
       --feature-rest-enabled-sql true \
       --feature-sdw true \
       --gateway-mode proxied \
       --gateway-user APEX_PUBLIC_USER \
       --password-stdin <<EOF
${SYSDBA_PASSWORD} as SYSDBA
EOF

  cp ords.war ${CATALINA_BASE}/webapps/

  check_apex ${CONNECTION}

  if [ ${APEX_OK} -eq 0 ]; then
    install_apex ${CONNECTION}
  fi

fi

if [ ! -f ${KEYSTORE_DIR}/keystore.jks ]; then
  echo "******************************************************************************"
  echo "Configure HTTPS." `date`
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
echo "Start Tomcat." `date`
echo "******************************************************************************"
${CATALINA_HOME}/bin/startup.sh

echo "******************************************************************************"
echo "Tail the catalina.out file as a background process" `date`
echo "and wait on the process so script never ends." `date`
echo "******************************************************************************"
tail -f ${CATALINA_BASE}/logs/catalina.out &
bgPID=$!
wait $bgPID
