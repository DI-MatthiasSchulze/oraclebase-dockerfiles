create or replace PACKAGE "CCFLAGS" as

  /*
  ** PLSQL Compiler-Flags
  **
  ** bedingte Compilierung, s. http://download.oracle.com/docs/cd/B28359_01/appdev.111/b28370/fundamentals.htm#insertedID9
  **
  ** ! können leider in SQL (Views) nicht verwendet werden !
  **
  ** Abfragen von Objekten mit gesetzten Compilerschaltern:     select * from ALL_PLSQL_OBJECT_SETTINGS where plsql_ccflags is not null;
  **
  */

  WINDOWS                     constant boolean := case when dbms_utility.port_string like 'IBMPC%' then true  else false end;
  LINUX                       constant boolean := case when dbms_utility.port_string like 'IBMPC%' then false else true  end;

  APEXFEATURES                constant boolean := true;    -- Oracle APEX Integration
  ORDFEATURES                 constant boolean := false;   -- Oracle Multimedia Integration

  LVSPWD                      constant boolean := false;   -- Password is stored as "LVS-Encrypted"

End CCFLAGS;
/