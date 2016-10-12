options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

libname M015_Out "&M015_Out.";
libname M025_Out "&M025_Out.";
libname M035_Out "&M035_Out.";
libname M073_Out "&M073_Out.";
libname Post008 "&Post008.";
libname Post070 "&Post070.";

%let path_dir_text_src = %GetParentFolder(0);
%put path_dir_text_src = &path_dir_text_src.;

%build_metadata_table(Post005_Datamarts)

%macro CodeGen_Wrapper(name_table);

%global _codegen_input_&name_table.;

proc sql noprint;
	select
		name_field
	into
		 :_codegen_input_&name_table. separated by " "

	from metadata_&name_table.
	;
quit;

%put _codegen_spaces_&name_table. = &&_codegen_input_&name_table..;

%mend CodeGen_Wrapper;

%CodeGen_Wrapper(member);
%CodeGen_Wrapper(outclaims);
%CodeGen_Wrapper(outpharmacy);
%CodeGen_Wrapper(reflines);

proc sql;
		create table outclaims_pre as
		select
			*
			,case when upcase(prm_util_type) = "DAYS" then prm_util else 0 end as prm_days
		from M073_Out.outclaims_prm
		order by sequencenumber
		;
quit;

data post070.outclaims (keep = &_codegen_input_outclaims.);
	set outclaims_pre;
run;

proc sql;
		create table outpharmacy_pre as
		select
			src.*
			,prv.prv_net_hier_1
		from M073_Out.Outpharmacy_prm as src
		left join M025_out.providers as prv
			on src.ProviderID eq prv.prv_id
		order by src.sequencenumber
		;
quit;

data post070.outpharmacy (keep = &_codegen_input_outpharmacy.);
	set outpharmacy_pre;
run;

data post070.ref_prm_line (keep = &_codegen_input_reflines.);
    set M015_Out.mr_line_info;
    rename
        mr_line = prm_line
        prm_line_desc1 = prm_line_category
        ;
run;

proc sql;
	create table member_limit as 
	select mt.member_id
		  ,mt.elig_month
		  ,mt.elig_status_1
		  ,mt.Cover_Medical
		  ,mt.MemMos
		  ,mem.age
		  ,mem.gender
		  ,mem.mem_name
		  ,mem.mem_address_line_1
		  ,mem.mem_address_line_2
		  ,mem.mem_city_state
		  ,mem.mem_state
		  ,mem.mem_zip5
		  ,mem.dob
	from M035_out.member_time as mt
	left join M035_out.member as mem
		on mt.member_id = mem.member_id
	where upcase(mt.cover_medical) = "Y"
	order by member_id
	;
quit;

proc summary nway missing data = member_limit;
	class member_id elig_month elig_status_1 cover_medical
		  age gender mem_name mem_address_line_1 mem_address_line_2 mem_city_state mem_state mem_zip5 dob;
	var memmos;
output out = member_pre_summ (drop = _type_) sum=;
run;

data post070.member (keep = &_codegen_input_member.);
	set member_pre_summ;
run;

data _null_;
	set M190_out.outclaims;
	file "K:\PHI\0273NYP\3.033-0273NYP(33-HH)\5-Support_Files\Data_Thru_201606_M6\190_PowerUser_DataMart_Client\outclaims.txt" dlm = ',';
	put &_codegen_input_outclaims.;
run;

data _null_;
	set M190_out.outpharmacy;
	file "K:\PHI\0273NYP\3.033-0273NYP(33-HH)\5-Support_Files\Data_Thru_201606_M6\190_PowerUser_DataMart_Client\outpharmacy.txt" dlm = ',';
	put &_codegen_input_outpharmacy.;
run;

data _null_;
	set M190_out.ref_prm_line;
	file "K:\PHI\0273NYP\3.033-0273NYP(33-HH)\5-Support_Files\Data_Thru_201606_M6\190_PowerUser_DataMart_Client\ref_prm_line.txt" dlm = ',';
	put &_codegen_input_reflines.;
run;

data _null_;
	set M190_out.member;
	file "K:\PHI\0273NYP\3.033-0273NYP(33-HH)\5-Support_Files\Data_Thru_201606_M6\190_PowerUser_DataMart_Client\member.txt" dlm = ',';
	put &_codegen_input_member.;
run;
