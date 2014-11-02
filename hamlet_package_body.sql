create or replace package body hamlet is

  current_execution number;
  current_testcase  number;
  
  type t_argument is record(
       arg_name  varchar2(30),
       data_type varchar2(30),
       arg_type  varchar2(30));
     
  type t_arg_list is table of t_argument /*index by binary_integer*/;



function get_run_string(p_pkg in varchar2, p_prc in varchar2) return varchar2 is
begin
  if p_pkg is null then
     return 'begin ' || p_prc || '; end;';
     else
     return 'begin ' || p_pkg || '.' || p_prc || '; end;';
  end if;
end;

procedure write_to_log(p_place in varchar2, p_message in varchar2, 
                       p_testsuite_id in number, p_execution_id in number,
                       p_sqlcode in number, p_sqlmessage in varchar2) is
  pragma autonomous_transaction;
begin
  insert into testing_log(log_id, place, message, testsuite_id, execution_id, sql_code, sql_message, executed_by, executed_on)
  values (hamlet_seq.nextval, p_place, p_message, p_testsuite_id, p_execution_id, p_sqlcode, p_sqlmessage, nvl(v('APP_USER'), user), sysdate);
  
  commit;
end;

procedure set_execution_params is
begin
  insert into execution_param (execution_param_id, test_execution_id, test_case_id, parameter_type, parameter_name, 
                               num_value,    str_value,    dat_value)
  select hamlet_seq.nextval, t.*
    from (select current_execution, test_case_id, parameter_type, parameter_name,
                 num_value,      str_value,    dat_value
            from test_param
           where test_case_id = current_testcase
           minus
          select test_execution_id, test_case_id, parameter_type, parameter_name,
                 num_value,    str_value,    dat_value
            from execution_param
           where test_case_id = current_testcase
             and test_execution_id = current_execution) t;
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
  
  current_execution := hamlet_seq.nextval;
  insert into test_execution(test_execution_id, test_suite_id, execution_date, execution_user)
  values (current_execution, p_testsuite_id, sysdate, nvl(v('APP_USER'), user));
  
  for i in (
    select s.script_owner, s.script_package, s.script_proc, s.run_seq, t.test_case_id
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
             execute immediate 
             'begin ' ||
              case when i.script_owner   is not null then i.script_owner   || '.' else null end ||
              case when i.script_package is not null then i.script_package || '.' else null end ||
              case when i.script_proc    is not null then i.script_proc    || ';' else null end ||
             'end;';
           exception
             when others then
               set_exec_param(PR_ACT, PR_EXCEPTION	, SQLCODE || ': ' || SQLERRM || chr(10) || dbms_utility.format_error_backtrace);
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

procedure run_testsuite(p_owner in varchar2, p_package in varchar2, p_procedure in varchar2) is
  ts_id number;
  err_count number;
begin
    select test_suite_id
    into ts_id
    from test_suite
   where owner = p_owner
     and nvl(package_name, '*') = nvl(p_package, '*')
     and procedure_name = p_procedure;
  
  run_testsuite(ts_id);
  
  select count(*)
    into err_count
    from test_result
   where test_suite_id = ts_id;
  
  if err_count = 0 then
     dbms_output.put_line('Test is successfully passed!');
  else
     dbms_output.put_line('Test is not passed! Found ' || err_count || ' errors. See view test_result for details.');
     dbms_output.put_line('Testsiute ID = ' || ts_id);
  end if;
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
   when not matched then insert (test_param_id, test_case_id, parameter_type, parameter_name, num_value)
                         values (hamlet_seq.nextval, nvl(p_test_case_id, current_testcase), p_type, p_name, p_value);
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
   when not matched then insert (test_param_id, test_case_id, parameter_type, parameter_name, str_value)
                         values (hamlet_seq.nextval, nvl(p_test_case_id, current_testcase), p_type, p_name, p_value);
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
   when not matched then insert (test_param_id, test_case_id, parameter_type, parameter_name, dat_value)
                         values (hamlet_seq.nextval, nvl(p_test_case_id, current_testcase), p_type, p_name, p_value);
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
   when not matched then insert (execution_param_id, test_execution_id, test_case_id,     parameter_type, parameter_name, num_value)
                         values (hamlet_seq.nextval, current_execution, current_testcase, p_type,         p_name,         p_value);
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
   when not matched then insert (execution_param_id, test_execution_id, test_case_id,     parameter_type, parameter_name, str_value)
                         values (hamlet_seq.nextval, current_execution, current_testcase, p_type,         p_name,         p_value);
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
   when not matched then insert (execution_param_id, test_execution_id, test_case_id,     parameter_type, parameter_name, dat_value)
                         values (hamlet_seq.nextval, current_execution, current_testcase, p_type,         p_name,         p_value);
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

function new_testsuite(p_description varchar2, p_parent_id number default null) return number is
  new_id number;
begin
  new_id := hamlet_seq.nextval;
  
  insert into test_suite (test_suite_id, parent_id, test_suite_description) 
  values (new_id, p_parent_id, p_description);
  
  return new_id;
end;

function new_testcase(p_testsuite_id number, p_description varchar2) return number is
  new_id number;
begin
  new_id := hamlet_seq.nextval;
  
  insert into test_case (test_case_id, test_suite_id, test_case_description) 
  values (new_id, p_testsuite_id, p_description);
  
  return new_id;
end;

function create_test_procedure(p_owner in varchar2, p_package in varchar2, p_procedure in varchar2, 
                               p_test_procedure_name in varchar2) return varchar2 is
  proc_body varchar2(4000);
  args t_arg_list;
  is_function boolean := false;
  
  function get_arg_name(p_arg_entry in varchar2, p_is_param in number) return varchar2 is
  -- p_is_param = 0 - variable
  -- p_is_param = 1 - parameter
  begin
    return case when p_is_param = 0 then 'V_' else null end ||
           nvl(p_arg_entry, 'RESULT');
  end;
begin
  select argument_name, data_type, in_out
    bulk collect into args
    from all_arguments aa
   where aa.owner = p_owner
     and (aa.package_name = p_package or p_package is null)
     and aa.object_name = p_procedure
   order by aa.position, aa.sequence;

  proc_body := 'create or replace procedure ' || p_test_procedure_name || ' is ' || chr(10);
  
  -- declaration part of procedure
  for i in args.first..args.last loop
    -- TODO: move v_func_result constant to settings or package constants
    proc_body := proc_body || '  ' || get_arg_name(args(i).arg_name, 0) || ' ' || args(i).data_type ||
       case when instr(args(i).data_type, 'VARCHAR') > 0 then '(4000)' else null end || ';' || chr(10);
    
    -- check is it function or procedure:
    is_function := is_function or (args(i).arg_name is null);
  end loop;
  
  proc_body := proc_body || 'begin' || chr(10);
  proc_body := proc_body || '  -- read parameter''s values from a database:' || chr(10);
  
  for i in args.first..args.last loop
    if args(i).arg_type in ('IN', 'IN/OUT') then
       proc_body := proc_body || '  hamlet.hamlet.get_exec_param(''' || get_arg_name(args(i).arg_name, 1) || ''', ' || 
           get_arg_name(args(i).arg_name, 0) || ');' || chr(10);
    end if;
  end loop;

  proc_body := proc_body || chr(10);
  proc_body := proc_body || '  -- execute function or procedure: ' || chr(10);
  proc_body := proc_body || '  ';
  
  if is_function then
     proc_body := proc_body || 'V_RESULT := ';
  end if;
  
  proc_body := proc_body || 
      case when p_owner     is not null then p_owner     || '.' else null end ||
      case when p_package   is not null then p_package   || '.' else null end ||
      case when p_procedure is not null then p_procedure || '(' else null end || chr(10);
  
  for i in args.first..args.last loop
    if args(i).arg_name is not null then
       proc_body := proc_body || '    ' || args(i).arg_name || ' => ' || get_arg_name(args(i).arg_name, 0) || 
          case when i = args.last then ');' else ',' end || chr(10);
    end if;
  end loop;
  
  proc_body := proc_body || chr(10);
  proc_body := proc_body || '  -- save result in a database: ' || chr(10);

  for i in args.first..args.last loop
    if args(i).arg_type in ('OUT', 'IN/OUT') then
       proc_body := proc_body || '  hamlet.hamlet.set_exec_param(hamlet.hamlet.PR_ACT, ''' || 
           get_arg_name(args(i).arg_name, 1) || ''', ' || 
           get_arg_name(args(i).arg_name, 0) || ');' || chr(10);
    end if;
  end loop;

  proc_body := proc_body || 'end;';

  return proc_body;
end;

/*function create_test_package() clob is
  pkg_decl clob;
begin
  return pkg_decl;
end;

function create_test_package_body() clob is
  pkg_body clob;
begin
  return pkg_body;
end;*/

procedure create_test(p_owner in varchar2, p_package in varchar2, p_procedure in varchar2, 
                      p_testsuite_description in varchar2 default null, p_include_in_package in number default 1, 
                      p_test_package_name in varchar2 default null, p_test_procedure_name in varchar2 default null) is
  test_suite number;
  
  pkg_declaration clob;
  pkg_body clob;
  proc_name varchar2(30);
  pkg_name varchar2(30);
begin
  insert into test_suite(test_suite_id, owner, package_name, procedure_name, include_in_package, test_suite_description)
  values (hamlet_seq.nextval, p_owner, p_package, p_procedure, p_include_in_package, p_testsuite_description)
  returning test_suite_id into test_suite;  
  
  proc_name := substr(nvl(p_test_procedure_name, 'test_proc_' || test_suite), 1, 30);
  
  if p_include_in_package = 0 then
     execute immediate 
     create_test_procedure(p_owner, p_package, p_procedure, proc_name);
  --else
     --execute immediate create_test_package();
     --execute immediate create_test_package_body();
  end if;
  
  insert into script(script_id, script_description, run_seq, script_type, test_suite_id, 
                     script_owner, script_package, script_proc)
  values (hamlet_seq.nextval, 'Simple script', 1, SC_BODY, test_suite, 'HAMLET', pkg_name, proc_name);
end;

procedure add_testcase(p_owner in varchar2, p_package in varchar2, p_procedure in varchar2, 
                       p_test_case_description in varchar2, p_parameters in param_list) is
  ts_id number;
  tc_id number;
begin
  select test_suite_id
    into ts_id
    from test_suite
   where owner = p_owner
     and nvl(package_name, '*') = nvl(p_package, '*')
     and procedure_name = p_procedure;

  insert into test_case(test_case_id, test_suite_id, test_case_description)
  values(hamlet_seq.nextval, ts_id, p_test_case_description)
  returning test_case_id into tc_id;
  
  forall i in p_parameters.first..p_parameters.last
    insert into test_param(test_param_id, test_case_id, parameter_type, 
                           parameter_name, num_value, str_value, dat_value)
    values(hamlet_seq.nextval, tc_id, p_parameters(i).param_type, p_parameters(i).param_name, 
           p_parameters(i).num_value, p_parameters(i).str_value, p_parameters(i).dat_value);

exception
  when no_data_found then
    raise_application_error(-20003, 'Testsuite for object ' ||
      case when p_owner     is not null then p_owner     || '.' else null end ||
      case when p_package   is not null then p_package   || '.' else null end ||
      case when p_procedure is not null then p_procedure else null end || ' not found. Testcase creation is impossible.');
end;

procedure grant_execution_to_user(p_username in varchar2) is
begin
  execute immediate 'grant select on hamlet_seq to ' || p_username;
  execute immediate 'grant select, insert, update on test_suite to '      || p_username;
  execute immediate 'grant select, insert, update on test_case to '       || p_username;
  execute immediate 'grant select, insert, update on test_param to '      || p_username;
  execute immediate 'grant select, insert, update on test_execution to '  || p_username;
  execute immediate 'grant select, insert, update on execution_param to ' || p_username;
  execute immediate 'grant select, insert, update on script to '          || p_username;
  execute immediate 'grant select, insert, update on testing_log to '     || p_username;
  execute immediate 'grant select  on test_result to '                    || p_username;
  execute immediate 'grant execute on hamlet to '                         || p_username;
end;

procedure grant_develop_to_user(p_username in varchar2) is
begin
  execute immediate 'grant all on hamlet_seq to '      || p_username;
  execute immediate 'grant all on test_suite to '      || p_username;
  execute immediate 'grant all on test_case to '       || p_username;
  execute immediate 'grant all on test_param to '      || p_username;
  execute immediate 'grant all on test_execution to '  || p_username;
  execute immediate 'grant all on execution_param to ' || p_username;
  execute immediate 'grant all on script to '          || p_username;
  execute immediate 'grant all on testing_log to '     || p_username;
  execute immediate 'grant all on test_result to '     || p_username;
  execute immediate 'grant all on hamlet to '          || p_username;
end;

end hamlet;
/
