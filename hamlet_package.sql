create or replace package hamlet is

SC_SETUP    constant varchar2(10) := 'SETUP';
SC_TEARDOWN constant varchar2(10) := 'TEARDOWN';
SC_BODY     constant varchar2(10) := 'BODY';

PR_IN  constant varchar2(3) := 'IN';
PR_EXP constant varchar2(3) := 'EXP';
PR_ACT constant varchar2(3) := 'ACT';
PR_ERR constant varchar2(3) := 'ERR';
PR_EXCEPTION constant varchar2(10) := 'EXCEPTION';

-- error constants
TESTSUITE_NOT_FOUND constant number := -20001;

type parameter is record(
     param_name varchar2(30),
     param_type varchar2(10),
     num_value  number,
     dat_value  date,
     str_value  varchar2(4000));

type param_list is table of parameter index by binary_integer;

procedure run_testsuite(p_testsuite_id number);
procedure run_testsuite(p_owner in varchar2, p_package in varchar2, p_procedure in varchar2);

procedure set_param(p_type varchar2, p_name varchar2, p_value number,   p_test_case_id number := null);
procedure set_param(p_type varchar2, p_name varchar2, p_value varchar2, p_test_case_id number := null);
procedure set_param(p_type varchar2, p_name varchar2, p_value date,     p_test_case_id number := null);

procedure set_exec_param(p_type varchar2, p_name varchar2, p_value number);
procedure set_exec_param(p_type varchar2, p_name varchar2, p_value varchar2);
procedure set_exec_param(p_type varchar2, p_name varchar2, p_value date);

procedure get_exec_param(p_name varchar2, p_value out number);
procedure get_exec_param(p_name varchar2, p_value out varchar2);
procedure get_exec_param(p_name varchar2, p_value out date);

function new_testsuite(p_description varchar2, p_parent_id number default null) return number;
function new_testcase(p_testsuite_id number, p_description varchar2) return number;

procedure create_test(p_owner in varchar2, p_package in varchar2, p_procedure in varchar2, 
                      p_testsuite_description in varchar2 default null, p_include_in_package in number default 1, 
                      p_test_package_name in varchar2 default null, p_test_procedure_name in varchar2 default null);

procedure add_testcase(p_owner in varchar2, p_package in varchar2, p_procedure in varchar2, 
                       p_test_case_description in varchar2, p_parameters in param_list); 

procedure grant_execution_to_user(p_username in varchar2);
procedure grant_develop_to_user(p_username in varchar2);
 
end hamlet;
/