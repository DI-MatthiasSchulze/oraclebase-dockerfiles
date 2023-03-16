create or replace PACKAGE "CCFLAGS" as

  /*
  ** PLSQL Compiler-Flags
  **
  ** bedingte Compilierung, s. http://download.oracle.com/docs/cd/B28359_01/appdev.111/b28370/fundamentals.htm#insertedID9
  **
  ** $if CCFLAGS.APEXFEATURES $then
  **   ...
  ** $end
  **
  ** ! können leider in SQL (Views) nicht verwendet werden !
  **
  ** Abfragen von Objekten mit gesetzten Compilerschaltern:     select * from ALL_PLSQL_OBJECT_SETTINGS where plsql_ccflags is not null;
  **
  */

  WINDOWS                     constant boolean := true ;   -- enable Windows-Specific code
  LINUX                       constant boolean := false;   -- enable Linux-Specific code

  APEXFEATURES                constant boolean := true;    -- Oracle APEX Integration
  ORDFEATURES                 constant boolean := false;   -- Oracle Multimedia Integration

  LVSPWD                      constant boolean := false;   -- Password is stored as "LVS-Encrypted"

End CCFLAGS;
/