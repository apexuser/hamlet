create user &&USER identified by &&PASSWORD
  default tablespace &&tablespace;

grant connect to &&USER;
grant resource to &&USER;

connect &&USER/&&PASSWORD

create sequence hamlet_seq;

create table test_suite( 
  test_suite_id          number not null,
  parent_id              number,
  test_suite_description varchar2(1000));
  
create table test_case( 
  test_case_id          number not null,
  test_suite_id         number,
  test_case_description varchar2(4000));

create table test_param(
  test_param_id  number not null,
  test_case_id   number,
  parameter_type varchar2(3),
  parameter_name varchar2(100),
  num_value      number,
  str_value      varchar2(4000),
  dat_value      date,
  lob_value      clob);

create table test_execution(
  test_execution_id number not null,
  test_suite_id     number,
  execution_date    date,
  execution_user    varchar2(100));

create table execution_param(
  execution_param_id number,
  test_execution_id  number,
  test_case_id       number,
  parameter_type     varchar2(3),
  parameter_name     varchar2(100),
  num_value          number,
  str_value          varchar2(4000),
  dat_value          date,
  lob_value          clob);

create table script(
  script_id          number not null,
  script_body        clob,
  script_description varchar2(1000),
  run_seq            number,
  script_type        varchar2(10),
  test_suite_id      number,
  script_package     varchar2(30),
  script_proc        varchar2(30));

create table testing_log(
  log_id       number not null,
  place        varchar2(255),
  message      varchar2(4000),
  testsuite_id number,
  execution_id number,
  sql_code     number,
  sql_message  varchar2(4000),
  executed_by  varchar2(100),
  executed_on  date);
  
alter table test_suite      add constraint pk_test_suite      primary key (test_suite_id);
alter table test_case       add constraint pk_test_case       primary key (test_case_id);
alter table test_execution  add constraint pk_test_execution  primary key (test_execution_id);
alter table script          add constraint pk_script          primary key (script_id);
alter table test_param      add constraint pk_test_param      primary key (test_param_id);
alter table execution_param add constraint pk_execution_param primary key (execution_param_id);
alter table testing_log     add constraint pk_log             primary key (log_id);

alter table test_suite      add constraint fk_parent_suite   foreign key (parent_id)         references test_suite    (test_suite_id);
alter table test_case       add constraint fk_case_suite     foreign key (test_suite_id)     references test_suite    (test_suite_id);
alter table test_execution  add constraint fk_exec_suite     foreign key (test_suite_id)     references test_suite    (test_suite_id);
alter table test_param      add constraint fk_param_case     foreign key (test_case_id)      references test_case     (test_case_id);
alter table execution_param add constraint fk_execparam_exec foreign key (test_execution_id) references test_execution(test_execution_id);
alter table script          add constraint fk_script_suite   foreign key (test_suite_id)     references test_suite    (test_suite_id);
alter table testing_log     add constraint fk_log_suite      foreign key (testsuite_id)      references test_suite    (test_suite_id);
alter table testing_log     add constraint fk_log_exec       foreign key (execution_id)      references test_execution(test_execution_id);

@hamlet_package.sql

quit
/
