create user &&USER identified by &&PASSWORD
  default tablespace &&tablespace;

grant connect to &&USER;
grant resource to &&USER;
grant create view to &&USER;
grant create procedure to &&USER;
grant unlimited tablespace to &&USER;

connect &&USER/&&PASSWORD

@schema_objects.sql

@hamlet_package.sql

@hamlet_package_body.sql

show errors
quit
/
