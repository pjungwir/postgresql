/* Processed by ecpg (regression mode) */
/* These include files are added by the preprocessor */
#include <ecpglib.h>
#include <ecpgerrno.h>
#include <sqlca.h>
/* End of automatic include section */
#define ECPGdebug(X,Y) ECPGdebug((X)+100,(Y))

#line 1 "without_overlaps.pgc"
#include <stdio.h>


#line 1 "regression.h"






#line 3 "without_overlaps.pgc"


/* exec sql whenever sqlerror  sqlprint ; */
#line 5 "without_overlaps.pgc"


/*
 * WITHOUT OVERLAPS needs the WITHOUT_LA lookahead token, which ecpg's lexer
 * has to produce the same way the backend's does.
 */
int
main(void)
{
	/* exec sql begin declare section */
		 
	
#line 15 "without_overlaps.pgc"
 int n ;
/* exec sql end declare section */
#line 16 "without_overlaps.pgc"


	ECPGdebug(1, stderr);
	{ ECPGconnect(__LINE__, 0, "ecpg1_regression" , NULL, NULL , NULL, 0); 
#line 19 "without_overlaps.pgc"

if (sqlca.sqlcode < 0) sqlprint();}
#line 19 "without_overlaps.pgc"

	{ ECPGsetcommit(__LINE__, "on", NULL);
#line 20 "without_overlaps.pgc"

if (sqlca.sqlcode < 0) sqlprint();}
#line 20 "without_overlaps.pgc"


	{ ECPGdo(__LINE__, 0, 1, NULL, 0, ECPGst_normal, "create table wo_test ( id int4range , valid_at daterange , primary key ( id , valid_at without overlaps ) )", ECPGt_EOIT, ECPGt_EORT);
#line 26 "without_overlaps.pgc"

if (sqlca.sqlcode < 0) sqlprint();}
#line 26 "without_overlaps.pgc"

	{ ECPGdo(__LINE__, 0, 1, NULL, 0, ECPGst_normal, "create unique index wo_test_idx on wo_test using gist ( valid_at , id without overlaps )", ECPGt_EOIT, ECPGt_EORT);
#line 28 "without_overlaps.pgc"

if (sqlca.sqlcode < 0) sqlprint();}
#line 28 "without_overlaps.pgc"


	{ ECPGdo(__LINE__, 0, 1, NULL, 0, ECPGst_normal, "insert into wo_test values ( '[1,2)' , '[2020-01-01,2021-01-01)' )", ECPGt_EOIT, ECPGt_EORT);
#line 30 "without_overlaps.pgc"

if (sqlca.sqlcode < 0) sqlprint();}
#line 30 "without_overlaps.pgc"

	/* overlaps the first row, so this fails */
	{ ECPGdo(__LINE__, 0, 1, NULL, 0, ECPGst_normal, "insert into wo_test values ( '[1,2)' , '[2020-06-01,2021-06-01)' )", ECPGt_EOIT, ECPGt_EORT);
#line 32 "without_overlaps.pgc"

if (sqlca.sqlcode < 0) sqlprint();}
#line 32 "without_overlaps.pgc"

	{ ECPGdo(__LINE__, 0, 1, NULL, 0, ECPGst_normal, "select count ( * ) from wo_test", ECPGt_EOIT, 
	ECPGt_int,&(n),(long)1,(long)1,sizeof(int), 
	ECPGt_NO_INDICATOR, NULL , 0L, 0L, 0L, ECPGt_EORT);
#line 33 "without_overlaps.pgc"

if (sqlca.sqlcode < 0) sqlprint();}
#line 33 "without_overlaps.pgc"

	printf("count = %d\n", n);

	{ ECPGdo(__LINE__, 0, 1, NULL, 0, ECPGst_normal, "drop table wo_test", ECPGt_EOIT, ECPGt_EORT);
#line 36 "without_overlaps.pgc"

if (sqlca.sqlcode < 0) sqlprint();}
#line 36 "without_overlaps.pgc"

	{ ECPGdisconnect(__LINE__, "ALL");
#line 37 "without_overlaps.pgc"

if (sqlca.sqlcode < 0) sqlprint();}
#line 37 "without_overlaps.pgc"


	return 0;
}
