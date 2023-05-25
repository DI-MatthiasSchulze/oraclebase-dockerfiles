create or replace procedure ANONYMOUS."_DBA_CONFIGURE"
 (strSchema                 Varchar2 default SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'),
  createTablespace          Boolean default true,   -- create the tablespace
  createSchema              Boolean default true,   -- create the schema
  createWorkspace           Boolean default true,   -- create the APEX workspace
  createApexAdmin           Boolean default true,   -- create ADMIN user in APEX workspace
  createApexUsers           Boolean default true,   -- create default users in APEX workspace
  insertDemoData            Boolean default true,   -- insert some initial demonstration data into the TEST tenant
  optionDashboard           Boolean default true,   -- install dashboard objects
  optionFiletransfer        Boolean default true,   -- create directories for file transfer
  optionSMS                 Boolean default true,   -- create acl entry for SMS gateway
  optionSMTP                Boolean default true,   -- create acl entry for SMTP mails
  optionTranslateMode       Boolean default false,  -- extend APEX for dynamic translations
  apexTablespace            Varchar2 default 'APEX',
  apexTablespaceFiles       Varchar2 default 'APEX_FILES',
  smtpHost                  Varchar2 default 'mail.smtp2go.com',
  smtpPort                  Number   default 465,
  ordsPath                  Varchar2 default lower(SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')),
  rootPath                  Varchar2 default '/apps/'||lower(SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')),
  imagesDir                 Varchar2 default 'images',
  filesDir                  Varchar2 default 'files',
  storageOptions            Varchar2 default 'size 100M autoextend on',
  ApexTablespaceOnly        Boolean default false,
  runIt                     Boolean default false,
  dropIt                    Boolean default false
 ) AUTHID CURRENT_USER as
  /*
  ** Erstellt und konfiguriert einen APEX-Workspace und das dazugehörige Schema (Schemaname == Workspace-Name).
  **
  ** runIt => true muss übergeben werden, um die Statements tatsächlich auszuführen. Ansonsten erfolgt nur
  ** die Ausgabe des entsprechenden Scripts auf der Konsole!
  **
  ** Verwendung:
  **
  ** neuen Workspace erstellen und konfigurieren:
  **
  **      begin ANONYMOUS."_DBA_CONFIGURE"('INTRACK_DEMO_0026', doit => true); end;
  **
  **
  **
  ** * aktuelles Schema wiederholt konfigurieren (nach Apex-Upgrade erforderlich)
  **
  **      begin ANONYMOUS."_DBA_CONFIGURE"(pDoit => true); end;
  **
  **
  **
  ** Aufruf der Prozedur muss durch einen Nutzer mit DBA Rolle erfolgen!
  ** erfordert GRANT INHERIT PRIVILEGES ON USER "SYS" TO PUBLIC;
  **
  **
  */

  vSchema varchar2(30) := strSchema;
  vApexSchema varchar2(30);

  v_uid   ALL_USERS.USER_ID%type;   -- User ID
  v_ts    varchar2(100);            -- Tablespace name

  /*
  ** ID of the Apex Workspace with the same name as the schema
  */
  v_wsid Number;

  n number;
  s varchar2(31768);

  /*
  ** Execute immediate or output command line
  */
  procedure x
    (stmt     varchar2,
     failsafe boolean default false
    )
  is
  begin
    DBMS_OUTPUT.Put_Line (stmt);
    DBMS_OUTPUT.Put_Line ('/');

    if runIt then

      if failsafe then
        begin
          execute immediate stmt;
        exception when others then
          DBMS_OUTPUT.Put_Line ('/* previous statement failed due to');
          DBMS_OUTPUT.Put_Line (SQLERRM);
          DBMS_OUTPUT.Put_Line ('(ignoring) */');
        end;

      else
        execute immediate stmt;
      end if;

    end if;
  end;

  /*
  ** grants a privilege to the CURRENT_SCHEMA
  */
  procedure g
    (priv varchar2,
     whom varchar2 default vSchema
    )
  is
  begin
    x('grant '||priv||' to '||whom);
  exception
    when others then
      DBMS_OUTPUT.Put_Line ('/*  Error during GRANT: '||SQLERRM||' */');
  end;

  /*
  ** Append a Host ACE
  */
  procedure aha
    (host varchar2,
     port number,
     prot varchar2,
     principal  varchar2
    )
  is
  begin
    x('begin sys.dbms_network_acl_admin.append_host_ace
     (host             => '''||host||''',
      lower_port       => '''||port||''',
      ace              => xs$ace_type
       (privilege_list => xs$name_list('''||prot||'''),
        granted        => true,
        principal_name => '''||principal||''',
        principal_type => XS_ACL.PTYPE_DB
       )
     ); end;');
    --DBMS_OUTPUT.Put_Line ('append_host_ace host='||host||' port='||port||' prot='||prot||' principal='||principal);
  exception
    when others then
      DBMS_OUTPUT.Put_Line ('/*  Error appending Host ACE for '||host||': '||SQLERRM||' */');
  end;

  /*
  ** Create an Apex User
  */
  procedure cu
   (p_user_name                         in varchar2,
    p_first_name                        in varchar2,
    p_last_name                         in varchar2,
    p_email_address                     in varchar2,
    p_web_password                      in varchar2,
    p_web_password_format               in varchar2,
    p_developer_privs                   in varchar2,
    p_default_schema                    in varchar2,
    p_change_password_on_first_use      in varchar2,
    p_first_password_use_occurred       in varchar2,
    p_allow_app_building_yn             in varchar2,
    p_allow_sql_workshop_yn             in varchar2,
    p_allow_websheet_dev_yn             in varchar2,
    p_allow_team_development_yn         in varchar2,
    p_allow_access_to_schemas           in varchar2
   )
  is
  begin
    x('begin apex_util.create_user (
      p_user_name                    => '''|| p_user_name                    ||''',
      p_first_name                   => '''|| p_first_name                   ||''',
      p_last_name                    => '''|| p_last_name                    ||''',
      p_email_address                => '''|| p_email_address                ||''',
      p_web_password                 => '''|| p_web_password                 ||''',
      p_web_password_format          => '''|| p_web_password_format          ||''',
      p_developer_privs              => '''|| p_developer_privs              ||''',
      p_default_schema               => '''|| p_default_schema               ||''',
      p_change_password_on_first_use => '''|| p_change_password_on_first_use ||''',
      p_first_password_use_occurred  => '''|| p_first_password_use_occurred  ||''',
      p_allow_app_building_yn        => '''|| p_allow_app_building_yn        ||''',
      p_allow_sql_workshop_yn        => '''|| p_allow_sql_workshop_yn        ||''',
      p_allow_websheet_dev_yn        => '''|| p_allow_websheet_dev_yn        ||''',
      p_allow_team_development_yn    => '''|| p_allow_team_development_yn    ||''',
      p_allow_access_to_schemas      => '''|| p_allow_access_to_schemas      ||'''); end;'
    );

  exception
    when others then
      DBMS_OUTPUT.Put_Line ('/* Error creating user '||p_user_name||':'||SQLERRM||' */');
  end;


  /*
  ** *******************************************************
  */
  procedure create_schema
  is
  begin
    DBMS_OUTPUT.Put_Line ('/* Setting up schema '||vSchema||'... */');
  --x('create user '||vSchema||' identified by oracle');
    x('create user '||vSchema||'');
    x('alter user '||vSchema||' default tablespace '||vSchema, failsafe=>true);
    x('alter user '||vSchema||' quota unlimited on '||vSchema, failsafe=>true);
  end;


  /*
  ** *******************************************************
  */
  procedure create_tablespace
   (p_tablespace                      in varchar2
   )
   is
    v_fn    varchar2(1000);           -- Datafile name inkl path
    n       Varchar2(1000);
    v_so    Varchar2(1000) := nvl(storageOptions, 'size 100M autoextend on');
  begin
    DBMS_OUTPUT.Put_Line ('/*  Checking/Creating Tablespace '||p_tablespace||' */');

    begin

      execute immediate 'begin select tablespace_name into :n from dba_tablespaces where TABLESPACE_NAME = :p_tablespace; end;'
      using in out n, p_tablespace
      ;

    exception when no_data_found then

      begin
        execute immediate 'begin select replace(replace(name, ''system01.'', '''||p_tablespace||'_01.''), ''SYSTEM01.'', '''||p_tablespace||'_01.'')
        into   :V_FN
        from   v$datafile
        where  lower(name) like ''%system01.dbf''; end;'
        using in out v_fn
        ;

      exception
        when others then
          DBMS_OUTPUT.Put_Line ('/* file name template not found, assuming OMF */');
          null;
      end;

      x('create tablespace '||p_tablespace||(case when v_fn is null then '' else ' datafile '''||v_fn||'''' end) ||' '||v_so, failsafe=>true);

    end;
  end;


  /*
  ** *******************************************************
  */
  procedure create_apex_workspace
  is
  begin
    DBMS_OUTPUT.Put_Line ('/*  creating workspace '||vSchema||'... */');
    x('begin wwv_flow_api.set_security_group_id(p_security_group_id => 10); end;');
    x('begin apex_instance_admin.add_workspace(
      P_WORKSPACE_ID         => null,
      P_WORKSPACE            => '''||vSchema||''',
      P_PRIMARY_SCHEMA       => '''||vSchema||'''
    ); end;');

    x('begin apex_instance_admin.enable_workspace(
        p_workspace       => '''||vSchema||'''
      ); end;'
    );
  exception
    when others then
      DBMS_OUTPUT.Put_Line ('/*  Error creating APEX workspace '||vSchema||': '||SQLERRM||' */');
  end;



  /*
  ** *******************************************************
  */
  procedure create_apex_users
  is
  begin
    x('begin wwv_flow_api.set_security_group_id(p_security_group_id => apex_util.find_security_group_id( p_workspace => '''||vSchema||''')); end;');

    if createApexAdmin then
      cu (p_user_name => 'admin', p_first_name => '',       p_last_name => 'Administrator',   p_email_address  => 'admins@dresden-informatik.de',  p_web_password  => 'admin', p_web_password_format => 'CLEAR_TEXT', p_developer_privs => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',     p_default_schema => vSchema, p_change_password_on_first_use => 'N', p_first_password_use_occurred  => 'Y', p_allow_app_building_yn => 'Y', p_allow_sql_workshop_yn => 'Y', p_allow_websheet_dev_yn => 'N', p_allow_team_development_yn => 'N', p_allow_access_to_schemas => '');
    end if;

    if createApexUsers then
      cu (p_user_name => 'TEST',  p_first_name => 'test',   p_last_name => 'test',            p_email_address  => 'info@dresden-informatik.de',    p_web_password  => 'test',  p_web_password_format => 'CLEAR_TEXT', p_developer_privs => '',                                                   p_default_schema => vSchema, p_change_password_on_first_use => 'N', p_first_password_use_occurred  => 'N', p_allow_app_building_yn => 'N', p_allow_sql_workshop_yn => 'N', p_allow_websheet_dev_yn => 'N', p_allow_team_development_yn => 'Y', p_allow_access_to_schemas => '');
      cu (p_user_name => 'USER1', p_first_name => 'User',   p_last_name => 'Eins',            p_email_address  => 'user1@dresden-informatik.de',   p_web_password  => 'user1', p_web_password_format => 'CLEAR_TEXT', p_developer_privs => '',                                                   p_default_schema => vSchema, p_change_password_on_first_use => 'N', p_first_password_use_occurred  => 'N', p_allow_app_building_yn => 'N', p_allow_sql_workshop_yn => 'N', p_allow_websheet_dev_yn => 'N', p_allow_team_development_yn => 'Y', p_allow_access_to_schemas => '');
      cu (p_user_name => 'USER2', p_first_name => 'User',   p_last_name => 'Zwei',            p_email_address  => 'user2@dresden-informatik.de',   p_web_password  => 'user2', p_web_password_format => 'CLEAR_TEXT', p_developer_privs => '',                                                   p_default_schema => vSchema, p_change_password_on_first_use => 'N', p_first_password_use_occurred  => 'N', p_allow_app_building_yn => 'N', p_allow_sql_workshop_yn => 'N', p_allow_websheet_dev_yn => 'N', p_allow_team_development_yn => 'Y', p_allow_access_to_schemas => '');
      cu (p_user_name => 'USER3', p_first_name => 'User',   p_last_name => 'Drei',            p_email_address  => 'user3@dresden-informatik.de',   p_web_password  => 'user3', p_web_password_format => 'CLEAR_TEXT', p_developer_privs => '',                                                   p_default_schema => vSchema, p_change_password_on_first_use => 'N', p_first_password_use_occurred  => 'N', p_allow_app_building_yn => 'N', p_allow_sql_workshop_yn => 'N', p_allow_websheet_dev_yn => 'N', p_allow_team_development_yn => 'Y', p_allow_access_to_schemas => '');
      cu (p_user_name => 'USER4', p_first_name => 'User',   p_last_name => 'Vier',            p_email_address  => 'user4@dresden-informatik.de',   p_web_password  => 'user4', p_web_password_format => 'CLEAR_TEXT', p_developer_privs => '',                                                   p_default_schema => vSchema, p_change_password_on_first_use => 'N', p_first_password_use_occurred  => 'N', p_allow_app_building_yn => 'N', p_allow_sql_workshop_yn => 'N', p_allow_websheet_dev_yn => 'N', p_allow_team_development_yn => 'Y', p_allow_access_to_schemas => '');
      cu (p_user_name => '789',   p_first_name => '',       p_last_name => 'MDE Anwender',    p_email_address  => 'info@dresden-informatik.de',    p_web_password  => '789',   p_web_password_format => 'CLEAR_TEXT', p_developer_privs => '',                                                   p_default_schema => vSchema, p_change_password_on_first_use => 'N', p_first_password_use_occurred  => 'N', p_allow_app_building_yn => 'N', p_allow_sql_workshop_yn => 'N', p_allow_websheet_dev_yn => 'N', p_allow_team_development_yn => 'Y', p_allow_access_to_schemas => '');
    end if;
  end;

  /*
  ** *******************************************************
  */
  procedure create_aq
  is
    n constant varchar2(30) := 'INTRACK_FI_TASK_QUEUE';
    s varchar2(1000);
  begin

    select max(name)
    into   s
    from   all_queues
    where  owner = vSchema
      and  name  = n
      and  ENQUEUE_ENABLED = 'YES'
      and  DEQUEUE_ENABLED = 'YES'
    ;

    if s is null then
      DBMS_OUTPUT.Put_Line ('/*  creating queue in '||vSchema||'... */');

      x('CREATE OR REPLACE TYPE '||vSchema||'.INTRACK_FI_TASK_TYPE AS OBJECT (
        task          VARCHAR2(255),
        info1         VARCHAR2(255),
        info2         VARCHAR2(255),
        info3         VARCHAR2(255),
        details       VARCHAR2(4000)
      )', failsafe => true);

      x('begin DBMS_AQADM.create_queue_table (
        queue_table        => '''||vSchema||'.'||n||'_QTAB'',
        queue_payload_type => '''||vSchema||'.INTRACK_FI_TASK_TYPE''
      ); end;', failsafe => true);

      x('begin DBMS_AQADM.create_queue (
        queue_name         => '''||vSchema||'.'||n||''',
        queue_table        => '''||vSchema||'.'||n||'_QTAB''
      ); end;', failsafe => true);

      x('begin DBMS_AQADM.start_queue (
        queue_name         => '''||vSchema||'.'||n||''',
        enqueue            => TRUE
      ); end;', failsafe => true);

    else
      DBMS_OUTPUT.Put_Line ('/* Queue '||vSchema||'.'||n||' is already installed */');
    end if;
  end;


  /*
  ** *******************************************************
  */
  procedure enable_ords
  is
  begin
    DBMS_OUTPUT.Put_Line ('/*  enabling ORDS ... */');

    x('begin ORDS.ENABLE_SCHEMA(p_enabled => TRUE,
      p_schema              => '''||vSchema||''',
      p_url_mapping_type    => ''BASE_PATH'',
      p_url_mapping_pattern => '''||ordsPath||''',
      p_auto_rest_auth      => FALSE); end;', failsafe => true);

  end;


  /*
  ** *******************************************************
  */
  procedure create_directories
  is
  begin
    DBMS_OUTPUT.Put_Line ('/*  creating directories ... */');

    x('create or replace directory '||vSchema||'_bilder as '''||rootPath||'/'||imagesDir||'''');

    if optionFiletransfer then
      x('create or replace directory '||vSchema||'_from_mobile         as '''||rootPath||'/'||filesDir||'/from-mobile'||'''         ');
      x('create or replace directory '||vSchema||'_to_mobile           as '''||rootPath||'/'||filesDir||'/to-mobile'||'''           ');
      x('create or replace directory '||vSchema||'_from_mobile_ok      as '''||rootPath||'/'||filesDir||'/from-mobile/ok'||'''      ');
      x('create or replace directory '||vSchema||'_from_mobile_err     as '''||rootPath||'/'||filesDir||'/from-mobile/err'||'''     ');
      x('create or replace directory '||vSchema||'_from_mobile_logs    as '''||rootPath||'/'||filesDir||'/from-mobile/logs'||'''    ');
      x('create or replace directory '||vSchema||'_from_mobile_script  as '''||rootPath||'/'||filesDir||'/from-mobile/script'||'''  ');
      x('create or replace directory '||vSchema||'_from_mobile_control as '''||rootPath||'/'||filesDir||'/from-mobile/control'||''' ');
    end if;

  end;


  /*
  ** *******************************************************
  */
  procedure grant_network_access
  is
  begin
    /*
    ** SMS Versand über gw.cmtelecom.com
    */
    if optionSMS then
      aha('gw.cmtelecom.com',  80, 'http',  vSchema);
      aha('gw.cmtelecom.com', 443, 'http',  vSchema);
      aha('api.sipgate.com',  443, 'http',  vSchema);
    end if;

    /*
    ** E-Mail Versand über smtp2go.com muss an das aktuelle APEX-schema gegrantet werden
    */
    if optionSMTP then
      aha(smtpHost, smtpPort, 'smtp',  vApexSchema);
    end if;
  end;


  /*
  ** *******************************************************
  */
  procedure grant_privileges
  is
  begin
    g ('DEBUG CONNECT SESSION'     );

    g ('ALTER SESSION'             );
    g ('CREATE CLUSTER'            );
    g ('CREATE DATABASE LINK'      );
    g ('CREATE DIMENSION'          );
    g ('CREATE INDEXTYPE'          );
    g ('CREATE JOB'                );
    g ('CREATE LIBRARY'            );
    g ('CREATE MATERIALIZED VIEW'  );
    g ('CREATE OPERATOR'           );
    g ('CREATE PROCEDURE'          );
    g ('CREATE SEQUENCE'           );
    g ('CREATE SESSION'            );
    g ('CREATE SYNONYM'            );
    g ('CREATE TABLE'              );
    g ('CREATE TRIGGER'            );
    g ('CREATE TYPE'               );
    g ('CREATE VIEW'               );

    g ('AQ_ADMINISTRATOR_ROLE'     );
    g ('AQ_USER_ROLE'              );
    g ('EXECUTE on SYS.DBMS_AQ'    );
    g ('EXECUTE on SYS.DBMS_ALERT' );
    g ('EXECUTE on SYS.DBMS_LOCK'  );
    g ('EXECUTE on SYS.DBMS_CRYPTO');

    g ('SELECT  on SYS.V_$MYSTAT'  );
    g ('SELECT  on SYS.V_$SESSION' );

    /*
    ** wegen ORA-00604, ORA-01031 Insufficient Privileges bei REST-Zugriffen
    */
    g ('SELECT  on ORDS_METADATA.ORDS_PARAMETERS'  );
    g ('SELECT  on ORDS_METADATA.ORDS_SCHEMAS' );

    if optionDashboard then
      g ('SELECT  on SYS.V_$OSSTAT');
      g ('SELECT  on SYS.V_$RECOVERY_FILE_DEST' );
    end if;

    g ('ALL  on DIRECTORY '||vSchema||'_BILDER' );

    if optionFiletransfer then
      g ('ALL  on DIRECTORY '||vSchema||'_FROM_MOBILE'         );
      g ('ALL  on DIRECTORY '||vSchema||'_TO_MOBILE'           );
      g ('ALL  on DIRECTORY '||vSchema||'_FROM_MOBILE_OK'      );
      g ('ALL  on DIRECTORY '||vSchema||'_FROM_MOBILE_ERR'     );
      g ('ALL  on DIRECTORY '||vSchema||'_FROM_MOBILE_LOGS'    );
      g ('ALL  on DIRECTORY '||vSchema||'_FROM_MOBILE_SCRIPT'  );
      g ('ALL  on DIRECTORY '||vSchema||'_FROM_MOBILE_CONTROL' );
    end if;

  end;


  /*
  ** *******************************************************
  */
--  procedure install_apex_application
--  is
--    l_installed_app_id number;
--  begin
--
--    x('begin apex_util.set_workspace('''||vSchema||'''); end;');
--    x('begin apex_application_install.set_workspace_id( apex_util.find_security_group_id( p_workspace => '''||vSchema||''')); end;');
--    x('begin apex_application_install.generate_application_id; end;');
--    x('begin apex_application_install.generate_offset; end;');
--    x('begin apex_application_install.set_schema('''||vSchema||'''); end;');
--    x('begin apex_application_install.set_application_alias('''||vSchema||'''); end;');
--  --x('apex_application_install.set_application_alias( 'F' || apex_application_install.get_application_id )');
--
--    DBMS_OUTPUT.Put_Line ('/* Installing packaged APP as #'||apex_application_install.get_application_id||'... */' );
--    x('declare app_id number; begin app_id := APEX_PKG_APP_INSTALL.INSTALL (
--      p_app_id              => '||packagedApp_Intrack||',
--      p_authentication_type => APEX_AUTHENTICATION.C_TYPE_APEX_ACCOUNTS,
--      p_schema              => '''||vSchema||'''
--    ); end;', failsafe => true);
--
--    x('begin '|| vApexSchema || '.wwv_flow_pkg_app_api.sync_application_metadata( p_security_group_id => '||v_wsid||', p_application_id => '||packagedApp_Intrack||' ); end;');
--
--    if optionDashboard then
--      x('begin apex_application_install.generate_application_id; end;');
--      x('begin apex_application_install.generate_offset; end;');
--
--      DBMS_OUTPUT.Put_Line ('/* Installing packaged APP as #'||apex_application_install.get_application_id||'... */' );
--      x('declare app_id number; begin app_id := APEX_PKG_APP_INSTALL.INSTALL (
--        p_app_id              => '||packagedApp_Dashboard||',
--        p_authentication_type => APEX_AUTHENTICATION.C_TYPE_APEX_ACCOUNTS,
--        p_schema              => '''||vSchema||'''
--      ); end;', failsafe => true);
--
--      x('begin '|| vApexSchema || '.wwv_flow_pkg_app_api.sync_application_metadata( p_security_group_id => '||v_wsid||', p_application_id => '||packagedApp_Dashboard||' ); end;');
--    end if;
--
--  end;


  /*
  ** *******************************************************
  */
  procedure insert_demo_data
  is
  begin
    DBMS_OUTPUT.Put_Line ('/* Installing demo data into TEST tenant... */' );
    x('begin '||vSchema||'.InsertDemoData(''TEST'', pStammdaten=>''J''); end;', failsafe => true);
  end;


  /*
  ** *******************************************************
  */
  procedure print_compile_errors
  is
    errors_detected Boolean := null;
  begin

    --DBMS_OUTPUT.Put_Line ('/* Recompiling the schema... */' );
    --x('begin DBMS_UTILITY.compile_schema('''||vSchema||'''); end; ');

    DBMS_OUTPUT.Put_Line ('/* *********************************************************************');

    for c in
     (Select ''||lower(replace(UER.type,' ', '_'))||'\'||upper(UER.name)||'.sql (' || lpad(UER.line,4) || ','||lpad(UER.POSITION,3)||'): '||UER.text as err
      From   user_errors     UER,
             all_objects     OBJ
      Where  UER.text not like '%Statement ignored%'
        and  OBJ.owner(+)       = vSchema
        and  OBJ.object_name(+) = UER.name
        and  OBJ.object_type(+) = UER.type
      order by OBJ.LAST_DDL_TIME desc, UER.line, UER.POSITION
     )
    Loop
      if errors_detected is null then
        DBMS_OUTPUT.Put_Line ('ERRORS:');
        errors_detected := true;
      end if;

      DBMS_OUTPUT.Put_Line (c.err);
    end loop;

    if errors_detected is null then
      DBMS_OUTPUT.Put_Line ('CONGRATULATIONS! NO ERRORS!');
    end if;

    DBMS_OUTPUT.Put_Line ('************************************************************************');
    DBMS_OUTPUT.Put_Line ('*/');
  end;

  /*
  ** *******************************************************
  */
  procedure extend_apex
  is
  begin
    for c in
     (select count(*) as VIEW_EXISTS
      from   all_views
      where  owner = vApexSchema
      and    view_name = 'V_APEX_USERINFO'
     )
    loop
      if c.VIEW_EXISTS = 0 then
        x('create or replace view '||vApexSchema||'.V_APEX_USERINFO as
          select U.USER_NAME,
                 U.FIRST_NAME,
                 U.LAST_NAME,
                 U.EMAIL_ADDRESS,
                 substr(translate(rawtohex(U.web_password2), ''0123456789ABCDEF'', ''0123456789''),1,8) as PWD
          from   APEX_APPLICATIONS A
          join   WWV_FLOW_FND_USER U
            on   U.SECURITY_GROUP_ID = A.WORKSPACE_ID
          where  A.APPLICATION_ID    = APEX_UTIL.GET_SESSION_STATE(''APP_ID'')
            and  U.USER_NAME         = APEX_UTIL.GET_SESSION_STATE(''APP_USER'')'
        );
        --DBMS_OUTPUT.Put_Line (vApexSchema||'.V_APEX_USERINFO created');
        x('create or replace public synonym V_APEX_USERINFO for '||vApexSchema||'.V_APEX_USERINFO');
        --DBMS_OUTPUT.Put_Line ('Public Synonym V_APEX_USERINFO created');

      end if;
    end loop;

    g ('SELECT  on '||vApexSchema||'.V_APEX_USERINFO' );


    for c in
     (select count(*) as VIEW_EXISTS
      from   all_views
      where  owner = vApexSchema
      and    view_name = 'V_APEX_TRANS_MAP'
     )
    loop
      if c.VIEW_EXISTS = 0 then
        x('create or replace view '||vApexSchema||'.V_APEX_TRANS_MAP as
          select f1.SECURITY_GROUP_ID as WORKSPACE_ID,
                 f1.id as APPLICATION_ID,
                 f1.last_updated_on,
                 f2.id as TRANSLATED_APPLICATION_ID,
                 f2.created_on,
                 m.TRANSLATION_FLOW_LANGUAGE_CODE LANGUAGE,
                 case when f2.created_on > f1.last_updated_on then 0 else 1 end as REQUIRES_SYNCHRONIZATION
          from   wwv_flows f1,
                 wwv_flows f2,
                 wwv_flow_language_map m
          where  f1.id = m.primary_language_flow_id
            and  f2.id = m.translation_flow_id'
        );
        --DBMS_OUTPUT.Put_Line (vApexSchema||'.V_APEX_TRANS_MAP created');
        x('create or replace public synonym V_APEX_TRANS_MAP for '||vApexSchema||'.V_APEX_TRANS_MAP');
        --DBMS_OUTPUT.Put_Line ('Public Synonym V_APEX_TRANS_MAP created');
      end if;
    end loop;

    g ('SELECT  on '||vApexSchema||'.V_APEX_TRANS_MAP', 'PUBLIC' );

    if optionTranslateMode then

      s := 'create or replace function '||vApexSchema||'.CREATE_DYNAMIC_TRANSLATIONS
       (strTranslateFromText in varchar2
       )
      return number is

        PRAGMA AUTONOMOUS_TRANSACTION;
        ts     timestamp := SYSTIMESTAMP;
        u      varchar2(100) := APEX_APPLICATION.g_user;

      begin
        if APEX_APPLICATION.G_FLOW_ID is null then
          raise_application_error(-20000, ''APP_ID is not defined'');
        end if;

        insert into WWV_FLOW_DYNAMIC_TRANSLATIONS$
         (FLOW_ID,
          TRANSLATE_TO_LANG_CODE,
          TRANSLATE_FROM_TEXT,
          TRANSLATE_TO_TEXT,
          CREATED_BY,
          CREATED_ON
         )
         (select PRIMARY_LANGUAGE_FLOW_ID,
                 TRANS_FLOW_LANG_CODE_ROOT,
                 strTranslateFromText,
                 strTranslateFromText,
                 u,
                 ts
          from   '||vApexSchema||'.wwv_flow_language_map
          where  PRIMARY_LANGUAGE_FLOW_ID = APEX_APPLICATION.G_FLOW_ID
          MINUS
          select FLOW_ID,
                 TRANSLATE_TO_LANG_CODE,
                 TRANSLATE_FROM_TEXT,
                 TRANSLATE_FROM_TEXT,
                 u,
                 ts
          from   WWV_FLOW_DYNAMIC_TRANSLATIONS$
          where  FLOW_ID = APEX_APPLICATION.G_FLOW_ID
            and  TRANSLATE_FROM_TEXT = strTranslateFromText
         );

        commit;

        return SQL%ROWCOUNT;
      end;';

      x(s);
      x('create or replace public synonym CREATE_DYNAMIC_TRANSLATIONS for '||vApexSchema||'.CREATE_DYNAMIC_TRANSLATIONS');

      g ('EXECUTE on '||vApexSchema||'.CREATE_DYNAMIC_TRANSLATIONS', 'PUBLIC');
    end if;

  end;


BEGIN

  /* determine current APEX schema */
  if not ApexTablespaceOnly then
    begin
      select table_owner
      into   vApexSchema
      from   all_synonyms
      where  synonym_name = 'APEX_APPLICATION'
        and  owner = 'PUBLIC'
      ;

    exception
      when no_data_found then
        DBMS_OUTPUT.Put_Line ('Error: APEX not installed');
        raise;
    end;
  end if;

  /* check existing schema */
  begin
    execute immediate 'begin select user_id
    into   :v_uid
    from   all_users
    where  upper(username) = '''||upper(vSchema)||'''; end;'
    using in out v_uid
    ;

  exception
    when no_data_found then
      null;
  end;

  if dropIt then
    DBMS_OUTPUT.Put_Line ('/* run the following statement to drop the workspace including all contents:');
    DBMS_OUTPUT.Put_Line ('');
    DBMS_OUTPUT.Put_Line ('begin APEX_INSTANCE_ADMIN.REMOVE_WORKSPACE('''||vSchema||''',''Y'',''Y''); end;');
    DBMS_OUTPUT.Put_Line ('*/');
    return;
  end if;

  if createTablespace then
    create_tablespace (apexTablespace);
    create_tablespace (apexTablespaceFiles);
    create_tablespace (vSchema);
    if ApexTablespaceOnly then
      return;
    end if;
  end if;

  if v_uid is null and createSchema then
    create_schema;
  end if;

  if not (vSchema = user) then
    x('ALTER SESSION SET CURRENT_SCHEMA = '||vSchema);
  end if;

  /* check existing APEX workspace */
  begin
    execute immediate 'begin :v_wsid := apex_util.find_security_group_id( p_workspace => :schema); end;'
    using out v_wsid, in vSchema
    ;

  exception
    when others then
      DBMS_OUTPUT.Put_Line ('/*  Failed to get workspace ID: '||SQLERRM||' */');
  end;

  if optionSMS or optionSMTP then
    grant_network_access;
  end if;

  if optionFiletransfer then
    create_directories;
  end if;

  if optionFiletransfer then
    create_aq;
  end if;

  grant_privileges;

  if v_wsid is null then
    if createWorkspace then
      create_apex_workspace;
    --else
    --  raise_application_error(-20000, 'APEX workspace "'||vSchema||'" does not exist, must be created first!');
    end if;
  end if;

  if createApexAdmin or createApexUsers then
    create_apex_users;
  end if;

  --enable_ords;

  if optionTranslateMode then
    extend_apex;
  end if;

  if insertDemoData then
    insert_demo_data;
  end if;

  --print_compile_errors;

end;
/

GRANT INHERIT PRIVILEGES ON USER "SYS" TO PUBLIC;
/
