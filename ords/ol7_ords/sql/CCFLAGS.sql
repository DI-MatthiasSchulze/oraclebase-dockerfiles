create or replace PACKAGE "CCFLAGS" as

  /*
  ** PLSQL Compiler-Flags
  **
  ** bedingte Compilierung, s. http://download.oracle.com/docs/cd/B28359_01/appdev.111/b28370/fundamentals.htm#insertedID9
  **
  ** $if CCFLAGS.WINDOWS $then
  **   ...
  ** $end
  **
  ** Abfragen von Objekten mit gesetzten Compilerschaltern:     select * from ALL_PLSQL_OBJECT_SETTINGS where plsql_ccflags is not null;
  **
  */

  WINDOWS                     constant boolean := case when dbms_utility.port_string like 'IBMPC%' then true  else false end;
  LINUX                       constant boolean := case when dbms_utility.port_string like 'IBMPC%' then false else true  end;

  APEXFEATURES                constant boolean := true;   -- Oracle APEX Integration
  ORDFEATURES                 constant boolean := true;   -- Oracle Multimedia Integration

  LVSPWD                      constant boolean := false;  -- Password is stored as "LVS-Encrypted"

  TRC_WARN                    constant boolean := true;   -- trace warnings, errors and success messages
  TRC_INFO                    constant boolean := true;   -- trace more messages
  TRC_DEBUG                   constant boolean := true;   -- trace all

  ENABLE_UTL_FILE             constant boolean := true;   -- Disable when EXECUTE on UTL_FILE wasn't grated
  ENABLE_UTL_HTTP             constant boolean := true;   -- Disable when EXECUTE on UTL_HTTP wasn't grated
  ENABLE_DBMS_ALERT           constant boolean := true;   -- Disable when EXECUTE on DBMS_ALERT wasn't grated
  ENABLE_DBMS_LOCK            constant boolean := true;   -- Disable when EXECUTE on DBMS_LOCK wasn't grated

End CCFLAGS;
/

--create or replace type wwv_flow_t_varchar2 as table of varchar2(32767 byte);
