create user hamlet identified by hamlet;

create sequence hamlet.seq;

create table hamlet.test_suite( 
  test_suite_id          number not null,
  parent_id              number,
  test_suite_description varchar2(1000));
  
create table hamlet.test_case( 
  test_case_id          number not null,
  test_suite_id         number,
  test_case_description varchar2(4000));

create table hamlet.test_param(
  test_param_id  number not null,
  test_case_id   number,
  parameter_type varchar2(3),
  parameter_name varchar2(100),
  num_value      number,
  str_value      varchar2(4000),
  dat_value      date,
  lob_value      clob);

create table hamlet.test_execution(
  test_execution_id number not null,
  test_suite_id     number,
  execution_date    date,
  execution_user    varchar2(100));

create table hamlet.execution_param(
  execution_param_id number,
  test_execution_id  number,
  test_case_id       number,
  parameter_type     varchar2(3),
  parameter_name     varchar2(100),
  num_value          number,
  str_value          varchar2(4000),
  dat_value          date,
  lob_value          clob);

create table hamlet.script(
  script_id          number not null,
  script_body        clob,
  script_description varchar2(1000),
  run_seq            number,
  script_type        varchar2(10),
  test_suite_id      number,
  script_package     varchar2(30),
  script_proc        varchar2(30));

create table hamlet.testing_log(
  log_id       number not null,
  place        varchar2(255),
  message      varchar2(4000),
  testsuite_id number,
  execution_id number,
  sql_code     number,
  sql_message  varchar2(4000),
  executed_by  varchar2(100),
  executed_on  date);
  
alter table hamlet.test_suite      add constraint pk_test_suite      primary key (test_suite_id);
alter table hamlet.test_case       add constraint pk_test_case       primary key (test_case_id);
alter table hamlet.test_execution  add constraint pk_test_execution  primary key (test_execution_id);
alter table hamlet.script          add constraint pk_script          primary key (script_id);
alter table hamlet.test_param      add constraint pk_test_param      primary key (test_param_id);
alter table hamlet.execution_param add constraint pk_execution_param primary key (execution_param_id);
alter table hamlet.testing_log     add constraint pk_log             primary key (log_id);

alter table hamlet.test_suite      add constraint fk_parent_suite   foreign key (parent_id)         references hamlet.test_suite    (test_suite_id);
alter table hamlet.test_case       add constraint fk_case_suite     foreign key (test_suite_id)     references hamlet.test_suite    (test_suite_id);
alter table hamlet.test_execution  add constraint fk_exec_suite     foreign key (test_suite_id)     references hamlet.test_suite    (test_suite_id);
alter table hamlet.test_param      add constraint fk_param_case     foreign key (test_case_id)      references hamlet.test_case     (test_case_id);
alter table hamlet.execution_param add constraint fk_execparam_exec foreign key (test_execution_id) references hamlet.test_execution(test_execution_id);
alter table hamlet.script          add constraint fk_script_suite   foreign key (test_suite_id)     references hamlet.test_suite    (test_suite_id);
alter table hamlet.testing_log     add constraint fk_log_suite      foreign key (testsuite_id)      references hamlet.test_suite    (test_suite_id);
alter table hamlet.testing_log     add constraint fk_log_exec       foreign key (execution_id)      references hamlet.test_execution(test_execution_id);

create or replace package hamlet is

SC_SETUP    constant varchar2(10) := 'SETUP';
SC_TEARDOWN constant varchar2(10) := 'TEARDOWN';
SC_BODY     constant varchar2(10) := 'BODY';

PR_IN  constant varchar2(3) := 'IN';
PR_EXP constant varchar2(3) := 'EXP';
PR_ACT constant varchar2(3) := 'ACT';
PR_ERR constant varchar2(3) := 'ERR';

procedure run_testsuite(p_testsuite_id number);

procedure set_param(p_type varchar2, p_name varchar2, p_value number,   p_test_case_id number := null);
procedure set_param(p_type varchar2, p_name varchar2, p_value varchar2, p_test_case_id number := null);
procedure set_param(p_type varchar2, p_name varchar2, p_value date,     p_test_case_id number := null);

procedure set_exec_param(p_type varchar2, p_name varchar2, p_value number);
procedure set_exec_param(p_type varchar2, p_name varchar2, p_value varchar2);
procedure set_exec_param(p_type varchar2, p_name varchar2, p_value date);

procedure get_exec_param(p_name varchar2, p_value out number);
procedure get_exec_param(p_name varchar2, p_value out varchar2);
procedure get_exec_param(p_name varchar2, p_value out date);

end hamlet;
/

create or replace package body hamlet is

  current_execution number;
  current_testcase  number;

-- ������ ������ ������� �������
function get_run_string(p_pkg in varchar2, p_prc in varchar2) return varchar2 is
begin
  if p_pkg is null then
     return 'begin ' || p_prc || '; end;';
     else
     return 'begin ' || p_pkg || '.' || p_prc || '; end;';
  end if;
end;

-- ������ � ���
procedure write_to_log(p_place in varchar2, p_message in varchar2, 
                       p_testsuite_id in number, p_execution_id in number,
                       p_sqlcode in number, p_sqlmessage in varchar2) is
  pragma autonomous_transaction;
begin
  insert into testing_log(log_id, place, message, testsuite_id, execution_id, sql_code, sql_message, executed_by, executed_on)
  values (tst_seq.nextval, p_place, p_message, p_testsuite_id, p_execution_id, p_sqlcode, p_sqlmessage, nvl(v('APP_USER'), user), sysdate);
  
  commit;
end;

procedure set_execution_params is
begin
  insert into execution_param (test_execution_id, test_case_id, parameter_type, parameter_name, 
                               num_value,    str_value,    dat_value)
  select current_execution, test_case_id, parameter_type, parameter_name,
         num_value,      str_value,    dat_value
    from test_param
   where test_case_id = current_testcase
   minus
  select test_execution_id, test_case_id, parameter_type, parameter_name,
         num_value,    str_value,    dat_value
    from execution_param
   where test_case_id = current_testcase
     and test_execution_id = current_execution;
end;

procedure testsuite_setup(p_testsuite_id in number, p_ok out boolean) is
  scr_num number := 0;
begin
  for i in (
    select s.script_package, s.script_proc, s.run_seq
      from script s
     where s.test_suite_id = p_testsuite_id
       and s.script_type = SC_SETUP
       and s.script_proc is not null
     order by s.run_seq) loop
       
      scr_num := i.run_seq;
      execute immediate get_run_string(i.script_package, i.script_proc);
  end loop;
  
  p_ok := true;
exception
  when others then
    write_to_log(SC_SETUP, 'Testsuite script #' || to_char(scr_num), p_testsuite_id, null, SQLCODE, SQLERRM);
    p_ok := false;
end;

procedure testsuite_teardown(p_testsuite_id in number) is
  scr_num number := 0;
begin
  for i in (
    select s.script_package, s.script_proc, s.run_seq
      from script s
     where s.test_suite_id = p_testsuite_id
       and s.script_type = SC_TEARDOWN
       and s.script_proc is not null
     order by s.run_seq) loop
       
      begin
        scr_num := i.run_seq;
        execute immediate get_run_string(i.script_package, i.script_proc);
      exception
        when others then
          write_to_log(SC_TEARDOWN, 
                      'Testsuite script #' || to_char(scr_num), p_testsuite_id, null, SQLCODE, SQLERRM);
      end;
  end loop;
end;

procedure run_testsuite(p_testsuite_id number) is
  v_ok boolean;
begin
  for i in (
      select test_suite_id 
        from test_suite
       where parent_id = p_testsuite_id) loop

      testsuite_setup(p_testsuite_id, v_ok);
      if v_ok then
         run_testsuite(i.test_suite_id);
      end if;
      testsuite_teardown(p_testsuite_id);
  end loop;
  
  current_execution := tst_seq.nextval;
  insert into test_execution(test_execution_id, test_suite_id, execution_date, execution_user)
  values (current_execution, p_testsuite_id, sysdate, nvl(v('APP_USER'), user));
  
  for i in (
    select s.script_package, s.script_proc, s.run_seq, t.test_case_id
      from script s,
           test_case t
     where s.test_suite_id = p_testsuite_id
       and t.test_suite_id = p_testsuite_id
       and s.script_type = SC_BODY
       and s.script_proc is not null
     order by s.run_seq) loop

      begin
        current_testcase := i.test_case_id;
        testsuite_setup(p_testsuite_id, v_ok);
        
        if v_ok then
           set_execution_params;
           begin
             execute immediate get_run_string(i.script_package, i.script_proc);
           exception
             when others then
               set_exec_param(PR_ACT, 'EXCEPTION', SQLCODE || ': ' || SQLERRM || chr(10) || dbms_utility.format_error_backtrace);
           end;
        end if;
        testsuite_teardown(p_testsuite_id);
        
      exception
        when others then
          write_to_log(SC_BODY, 
                      'Unhandled exception', p_testsuite_id, null, SQLCODE, SQLERRM);
      end;

  end loop;

  current_testcase := null;
  current_execution := null;
  
  exception
    when others then
      write_to_log(SC_BODY, 
                      'General exception', p_testsuite_id, null, SQLCODE, SQLERRM);
      testsuite_teardown(p_testsuite_id);
end;

procedure set_param(p_type varchar2, p_name varchar2, p_value number, p_test_case_id number := null) is
begin
  merge into test_param tp
  using (select nvl(p_test_case_id, current_testcase) cid, p_type pt, p_name pn
           from dual
         ) op on (op.cid = tp.test_case_id
              and op.pt  = tp.parameter_type
              and op.pn  = tp.parameter_name)
   when matched then update set tp.num_value = p_value
  where tp.test_case_id = nvl(p_test_case_id, current_testcase)
    and tp.parameter_type = p_type
    and tp.parameter_name = p_name
   when not matched then insert (test_case_id, parameter_type, parameter_name, num_value)
                         values (nvl(p_test_case_id, current_testcase), p_type, p_name, p_value);
end;

procedure set_param(p_type varchar2, p_name varchar2, p_value varchar2, p_test_case_id number := null) is
begin
  merge into test_param tp
  using (select nvl(p_test_case_id, current_testcase) cid, p_type pt, p_name pn
           from dual
         ) op on (op.cid = tp.test_case_id
              and op.pt  = tp.parameter_type
              and op.pn  = tp.parameter_name)
   when matched then update set tp.str_value = p_value
  where tp.test_case_id = nvl(p_test_case_id, current_testcase)
    and tp.parameter_type = p_type
    and tp.parameter_name = p_name
   when not matched then insert (test_case_id, parameter_type, parameter_name, str_value)
                         values (nvl(p_test_case_id, current_testcase), p_type, p_name, p_value);
end;

procedure set_param(p_type varchar2, p_name varchar2, p_value date, p_test_case_id number := null) is
begin
  merge into test_param tp
  using (select nvl(p_test_case_id, current_testcase) cid, p_type pt, p_name pn
           from dual
         ) op on (op.cid = tp.test_case_id
              and op.pt  = tp.parameter_type
              and op.pn  = tp.parameter_name)
   when matched then update set tp.dat_value = p_value
  where tp.test_case_id = nvl(p_test_case_id, current_testcase)
    and tp.parameter_type = p_type
    and tp.parameter_name = p_name
   when not matched then insert (test_case_id, parameter_type, parameter_name, dat_value)
                         values (nvl(p_test_case_id, current_testcase), p_type, p_name, p_value);
end;

procedure set_exec_param(p_type varchar2, p_name varchar2, p_value number) is
begin
  merge into execution_param ep
  using (select current_execution eid, current_testcase cid, p_type pt, p_name pn
           from dual
         ) tp on (lnnvl(tp.eid <> ep.test_execution_id)
              and tp.cid = ep.test_case_id
              and tp.pt  = ep.parameter_type
              and tp.pn  = ep.parameter_name)
   when matched then update set ep.num_value = p_value
  where lnnvl(ep.test_execution_id <> current_execution)
    and ep.test_case_id = current_testcase
    and ep.parameter_type = p_type
    and ep.parameter_name = p_name
   when not matched then insert (test_execution_id, test_case_id,     parameter_type, parameter_name, num_value)
                         values (current_execution, current_testcase, p_type,         p_name,         p_value);
end;

procedure set_exec_param(p_type varchar2, p_name varchar2, p_value varchar2) is
begin
  merge into execution_param ep
  using (select current_execution eid, current_testcase cid, p_type pt, p_name pn
           from dual
         ) tp on (lnnvl(tp.eid <> ep.test_execution_id)
              and tp.cid = ep.test_case_id
              and tp.pt  = ep.parameter_type
              and tp.pn  = ep.parameter_name)
   when matched then update set ep.str_value = p_value
  where lnnvl(ep.test_execution_id <> current_execution)
    and ep.test_case_id = current_testcase
    and ep.parameter_type = p_type
    and ep.parameter_name = p_name
   when not matched then insert (test_execution_id, test_case_id,     parameter_type, parameter_name, str_value)
                         values (current_execution, current_testcase, p_type,         p_name,         p_value);
end;

procedure set_exec_param(p_type varchar2, p_name varchar2, p_value date) is
begin
  merge into execution_param ep
  using (select current_execution eid, current_testcase cid, p_type pt, p_name pn
           from dual
         ) tp on (lnnvl(tp.eid <> ep.test_execution_id)
              and tp.cid = ep.test_case_id
              and tp.pt  = ep.parameter_type
              and tp.pn  = ep.parameter_name)
   when matched then update set ep.dat_value = p_value
  where lnnvl(ep.test_execution_id <> current_execution)
    and ep.test_case_id = current_testcase
    and ep.parameter_type = p_type
    and ep.parameter_name = p_name
   when not matched then insert (test_execution_id, test_case_id,     parameter_type, parameter_name, dat_value)
                         values (current_execution, current_testcase, p_type,         p_name,         p_value);
end;

procedure get_exec_param(p_name varchar2, p_value out number) is
begin
  select num_value
    into p_value
    from test_param tp
   where tp.test_case_id = current_testcase
     and tp.parameter_type = PR_IN
     and tp.parameter_name = p_name;
  
  exception
    when no_data_found then
      raise_application_error(-20001, 'Parameter value not set: test_case_id = ' || to_char(current_testcase) || 
                                      ', p_type = ' || PR_IN || ', p_name = ' || p_name);
    when too_many_rows then
      raise_application_error(-20002, 'Parameter has many values: test_case_id = ' || to_char(current_testcase) || 
                                      ', p_type = ' || PR_IN || ', p_name = ' || p_name);
end;

procedure get_exec_param(p_name varchar2, p_value out varchar2) is
begin
  select str_value
    into p_value
    from test_param tp
   where tp.test_case_id = current_testcase
     and tp.parameter_type = PR_IN
     and tp.parameter_name = p_name;
  
  exception
    when no_data_found then
      raise_application_error(-20001, 'Parameter value not set: test_case_id = ' || to_char(current_testcase) || 
                                      ', p_type = ' || PR_IN || ', p_name = ' || p_name);
    when too_many_rows then
      raise_application_error(-20002, 'Parameter has many values: test_case_id = ' || to_char(current_testcase) || 
                                      ', p_type = ' || PR_IN || ', p_name = ' || p_name);
end;

procedure get_exec_param(p_name varchar2, p_value out date) is
begin
  select dat_value
    into p_value
    from test_param tp
   where tp.test_case_id = current_testcase
     and tp.parameter_type = PR_IN
     and tp.parameter_name = p_name;
  
  exception
    when no_data_found then
      raise_application_error(-20001, 'Parameter value not set: test_case_id = ' || to_char(current_testcase) || 
                                      ', p_type = ' || PR_IN || ', p_name = ' || p_name);
    when too_many_rows then
      raise_application_error(-20002, 'Parameter has many values: test_case_id = ' || to_char(current_testcase) || 
                                      ', p_type = ' || PR_IN || ', p_name = ' || p_name);
end;

/*function get_param(p_name varchar2, p_test_case_id number, p_type varchar2) return varchar2;
function get_param(p_name varchar2, p_test_case_id number, p_type varchar2) return date;*/

end hamlet;
/