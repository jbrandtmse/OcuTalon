# Story 23.8 Task 0: the read-only SQL user mechanism, measured on a lane-B throwaway

Measured 2026-11-15 on a throwaway stack of the base image `ocutalon-iris-base:2026.3.0AI.154.0` (IRIS build 154, ARM64, namespace OCUTALON, installer run, production up), by a temporary test class `OcuTalon.Test.Checks.SqlTask0` (deleted after the measurement). Fixture user `zzSqlTask0`, role `zzSqlTask0Role`, JDBC `%Library.SQLConnection` `zzSqlTask0` (URL `jdbc:IRIS://127.0.0.1:<SSPort>/OCUTALON`, classpath the image's own `intersystems-jdbc-3.11.0.jar`), tables `zzTask0.*` with SELECT granted on four of five. The password is a random 44-character Base64 string and is never printed.

## Verdict: HALT, item (a)

| Item | Result |
|---|---|
| Refusals (INSERT, UPDATE, DELETE, TRUNCATE, CREATE TABLE, CREATE VIEW, ALTER TABLE, DROP TABLE, a self-GRANT, a SELECT of an ungranted table, `CALL` of an unknown procedure, `DELETE ...; SELECT 1`) | PASS. Each is refused by IRIS over `Statement.Execute`: SQLCODE -99 (privilege violation), -112 (GRANT), -428, -25. Every fixture table kept its rows and definition, and `Made` was never created. |
| (a) sessions, exactly one service, SQL only | FAIL. See below. |
| (b) no extra resources | The role holds only `%DB_OCUTALON_DATA:R` and `%DB_OCUTALON_CODE:R`. The CODE database is needed (below), which the gate's wording ("other than %DB_OCUTALON_DATA:R") does not allow. |
| (c) JDBC loopback on the shipped image, no new dependency | PASS. `/usr/bin/java` and `dev/java/lib/1.8/intersystems-jdbc-3.11.0.jar` are in the image. The Java gateway starts on the first call. |
| (d) the password in the CPF, audit, messages, trace, logs | PASS. No hit in the CPF, `mgr/` (all files, journal included), the audit log (52,098 rows), the event log (76 rows); the connection record and the stored node hold no password and `pwd` is empty after the save. |

### (a): why it fails

- The JDBC loopback logs in through `%Service_Bindings`, not `%Service_SQL`. With `%Service_SQL` disabled the connection and SELECT still work. With `%Service_Bindings` disabled the connect fails ("Communication link failure: Access Denied"). The failed logins are audited with `Service name: %Service_Bindings`. The server job is `%SYS.DBSRV.1`.
- `%Service_Bindings` is the Object and Native binding service. It has no `%Service_Bindings` resource (`Security.Resources.Exists` is 0), so no role can withhold it: every user with a password logs in through it.
- The reader can open more than one kind of session. Services that are enabled, take a password and give the user USE (public U, held by every user): `%Service_Terminal`, `%Service_CallIn`, `%Service_EscalateLogin`, `%Service_MCPGateway`, `%Service_WebGateway`; no resource at all: `%Service_Bindings`, `%Service_GetInfo`.
- Over HTTP to the instance's web server with the reader's credentials: `/csp/sys/UtilHome.csp` answers 200 and its title is "IRIS - Home" (the Management Portal home); `/csp/sys/exp/%25CSP.UI.Portal.SQL.Home.zen` answers 200 with a login page (no privilege); `/api/mgmnt/` 403 (namespace USER), `/api/docdb/v1/OCUTALON/` 403, `/api/atelier/` 401. Control without credentials: `/api/mgmnt/` 401. 23 enabled web applications take a password and carry no resource.
- The Native API (`%Net.DB.DataSource`) connects with the reader's credentials (same server routine `%SYS.DBSRV.1`), but every global read, global write and class-method call is refused with `<PROTECT>` (inference: `%Service_Native` has no public permission and the role does not hold it).
- The installer cannot close these without changing instance-wide service settings, which are the same for every IRIS user.

### Findings that change the design (for the Planner's ruling)

1. **D1 is not what the spec expects.** With no role at all and a SQL `SELECT` grant on one table, the user connects and selects (0.023 s). Without any SQL grant it is refused at login ("Insufficient privilege for namespace OCUTALON ... resource %DB_OCUTALON_CODE required", `Access Denied`). With a role holding `%DB_OCUTALON_DATA:R` only: refused without a grant, works with a grant. With `%DB_OCUTALON_DATA:R` and `%DB_OCUTALON_CODE:R`: the connect always works, an ungranted table gives SQLCODE -99. So the role is only needed to make the connect succeed before any grant exists, and it needs the CODE database too.
2. **The JDBC `executeQuery` path refuses a non-query on the client** ("executeQuery called with a non-query"), before IRIS sees it. Only `Statement.Execute` reaches IRIS, so a product that must have IRIS refuse the text has to use `Execute` (the SQLCODE is then -99).
3. A query timeout works: `SetQueryTimeout(2)` on a 17-way self join ended after 2.099 s with SQLCODE -450.

## Measurements

First connect: 4.0 to 5.1 s when it also started the Java gateway (two runs; the login itself failed on a missing resource), 0.03 to 0.94 s once the gateway was up (three runs). Second and third connects (one open while the next is made): 0.009 to 0.075 s. A granted SELECT: 0.014 to 0.044 s.

The connection definition is stored at `^%SYS("sql","ODBCCONNECTION","DATA")` (system-wide, not in OCUTALON); the saved `pwd` property is empty and the wallet secret `%SQLGateway.<name>` exists. The instance's password pattern is `3.255ANP` and accepts the generated 44-character password. `%Service_CallIn` has public permission U; `%Service_SQL` U; `%Service_Native`, `%Gateway_SQL`, `%Gateway_Object`, `%DB_OCUTALON_DATA` and `%DB_OCUTALON_CODE` have none.

Parse-only `%SQL.Statement.%Prepare` in OCUTALON (Task 0 (d)): `SELECT`, a lower-case `select` with spaces, a trailing `;`, `WITH ... SELECT`, `SELECT ... UNION SELECT` and `EXPLAIN SELECT 1` all prepare with `%Metadata.statementType` 1. `SELECT 1; DELETE ...` is refused at `%Prepare` (SQLCODE -25, "Input (;) encountered after end of query"). INSERT is 2, UPDATE 3, DELETE 4, CREATE TABLE 9, DROP TABLE 11. `CALL` of an unknown procedure (-428), an empty string (-51) and a truncated SELECT (-1) are refused at `%Prepare`. The rule `statementType = 1` therefore admits `EXPLAIN` as well as `SELECT`.

Not measured, because the run stopped at the gate: the messages and trace of a running product (no product code exists yet; no message of this run names a password), and the production job's own right to read the wallet secret.

## Raw lines

```
password length 44
build IRIS for UNIX (Ubuntu Server LTS for ARM64 Containers) 2026.3.0AI (Build 154U) Thu Sep 24 2026 10:05:18 EDT ns OCUTALON user irisowner ssport 1972
java present 1 jar /usr/irissys/dev/java/lib/1.8/intersystems-jdbc-3.11.0.jar
fixture state Gr=3 rows, 2 cols, 11 chars;Un=3 rows, 2 cols, 11 chars;Dm=3 rows, 2 cols, 11 chars;Al=3 rows, 2 cols, 11 chars;Dr=3 rows, 2 cols, 11 chars;Made=absent;
password pattern 3.255ANP validate 1
security objects created
grants Gr:ok Dm:ok Al:ok Dr:ok n:ok
privilege check Gr select 1, Un select 0, Gr insert 0
connection zzSqlTask0 saved 1 , pwd property after save is empty
connection zzSqlTask0n saved 1 , pwd property after save is empty
connection stored at ^%SYS("sql","ODBCCONNECTION","DATA"), pwd piece in stored node contains the password 0 (16:196chars,17:198chars,)
wallet secret exists 1
(a) first connect 0.938 s ok
(a) granted select over Execute: ran, result set 1, rows 3
(a) select took 0.118 s
(a) granted select over ExecuteQuery: ran, rows 1
(a) uncached select shape: ran, rows 2
(a) values read back 1=Gr1,2=Gr2,3=Gr3,
(a) process of the reader: pid 6476 user zzSqlTask0 routine %SYS.DBSRV.1 jobtype 28 client com.intersystems.gateway.JavaGateway ns OCUTALON
(a) second connect 0.042 s ok
(a) a third connect while the second is open 0.075 s ok
(b) Execute INSERT INTO zzTask0.Dm (Id, V) VALUES (99, 'x') -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException  [SQLCODE: <-99>:<Privilege violation>]
(b) Query INSERT INTO zzTask0.Dm (Id, V) VALUES (99, 'x') -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException com.intersystems.jdbc.IRISStatement.Query(IRISStatement.java:223) executeQuery called with a non-query.
(b) Execute UPDATE zzTask0.Dm SET V = 'x' -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException  [SQLCODE: <-99>:<Privilege violation>]
(b) Query UPDATE zzTask0.Dm SET V = 'x' -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException com.intersystems.jdbc.IRISStatement.Query(IRISStatement.java:223) executeQuery called with a non-query.
(b) Execute DELETE FROM zzTask0.Dm -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException  [SQLCODE: <-99>:<Privilege violation>]
(b) Query DELETE FROM zzTask0.Dm -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException com.intersystems.jdbc.IRISStatement.Query(IRISStatement.java:223) executeQuery called with a non-query.
(b) Execute TRUNCATE TABLE zzTask0.Dm -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException  [SQLCODE: <-99>:<Privilege violation>]
(b) Query TRUNCATE TABLE zzTask0.Dm -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException com.intersystems.jdbc.IRISStatement.Query(IRISStatement.java:223) executeQuery called with a non-query.
(b) Execute CREATE TABLE zzTask0.Made (Id INTEGER) -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException  [SQLCODE: <-99>:<Privilege violation>]
(b) Query CREATE TABLE zzTask0.Made (Id INTEGER) -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException com.intersystems.jdbc.IRISStatement.Query(IRISStatement.java:223) executeQuery called with a non-query.
(b) Execute ALTER TABLE zzTask0.Al ADD COLUMN Extra INTEGER -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException  [SQLCODE: <-99>:<Privilege violation>]
(b) Query ALTER TABLE zzTask0.Al ADD COLUMN Extra INTEGER -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException com.intersystems.jdbc.IRISStatement.Query(IRISStatement.java:223) executeQuery called with a non-query.
(b) Execute DROP TABLE zzTask0.Dr -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException  [SQLCODE: <-99>:<Privilege violation>]
(b) Query DROP TABLE zzTask0.Dr -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException com.intersystems.jdbc.IRISStatement.Query(IRISStatement.java:223) executeQuery called with a non-query.
(b) Execute SELECT COUNT(*) FROM zzTask0.Un -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException  [SQLCODE: <-99>:<Privilege violation>]
(b) Query SELECT COUNT(*) FROM zzTask0.Un -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException  [SQLCODE: <-99>:<Privilege violation>]
(b) Execute GRANT SELECT ON zzTask0.Un TO zzSqlTask0 -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException  [SQLCODE: <-112>:<Access violation>]
(b) Query GRANT SELECT ON zzTask0.Un TO zzSqlTask0 -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException com.intersystems.jdbc.IRISStatement.Query(IRISStatement.java:223) executeQuery called with a non-query.
(b) Execute CREATE VIEW zzTask0.Vw AS SELECT * FROM zzTask0.Gr -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException  [SQLCODE: <-99>:<Privilege violation>]
(b) Query CREATE VIEW zzTask0.Vw AS SELECT * FROM zzTask0.Gr -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException com.intersystems.jdbc.IRISStatement.Query(IRISStatement.java:223) executeQuery called with a non-query.
(b) Execute CALL %SYSTEM.SQL_Functions.Foo() -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException  [SQLCODE: <-428>:<Stored procedure not found>]
(b) Query CALL %SYSTEM.SQL_Functions.Foo() -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException  [SQLCODE: <-428>:<Stored procedure not found>]
(b) Execute DELETE FROM zzTask0.Gr; SELECT 1 -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException  [SQLCODE: <-25>:<Input encountered after end of query>]
(b) Query DELETE FROM zzTask0.Gr; SELECT 1 -> ERROR sqlcode -400 <GATEWAY> java.sql.SQLException com.intersystems.jdbc.IRISStatement.Query(IRISStatement.java:223) executeQuery called with a non-query.
(b) state before Gr=3 rows, 2 cols, 11 chars;Un=3 rows, 2 cols, 11 chars;Dm=3 rows, 2 cols, 11 chars;Al=3 rows, 2 cols, 11 chars;Dr=3 rows, 2 cols, 11 chars;Made=absent;
(b) state after  Gr=3 rows, 2 cols, 11 chars;Un=3 rows, 2 cols, 11 chars;Dm=3 rows, 2 cols, 11 chars;Al=3 rows, 2 cols, 11 chars;Dr=3 rows, 2 cols, 11 chars;Made=absent;
(b) tables unchanged 1, statements that did not error 0 (a SELECT of a granted table is not among them)
(timeout) a 17-way self join of 3 rows with a 2 s query timeout: ERROR sqlcode -400 <GATEWAY> java.sql.SQLException  [SQLCODE: <-450>:<Request timed out due to user timeout>] after 2.099 s
(c) no-role user connected in 0.023 s
(c) no-role user SELECT of a granted table (Gr): ran, rows 1
(c) role of the main user: resources %DB_OCUTALON_CODE:R,%DB_OCUTALON_DATA:R grantedroles
(b) resources checked 207
(b) resources the user holds beyond a user with no role: %DB_OCUTALON_CODE:READ (no role: ); %DB_OCUTALON_DATA:READ (no role: );
(b) every %Development/%Admin_/%Ens_/%DB_ resource the user can reach, public ones included: %DB_ENSLIB:READ; %DB_HSLIB:READ; %DB_IRISLIB:READ; %DB_IRISLOCALDATA:READ; %DB_IRISTEMP:READ,WRITE; %DB_OCUTALON_CODE:READ; %DB_OCUTALON_DATA:READ; %DB_OCUTALON_PUBLIC:READ;
(b) user record roles 'zzSqlTask0Role' escalation '' enabled 1 ns OCUTALON changepw 0
(b) holds %All 0, %Admin_Secure USE 0, %Development USE 0, %DB_OCUTALON_CODE READ, %DB_%DEFAULT
(a) services that are enabled, take a password and give the user USE: %Service_Bindings(no such resource, so no check); %Service_CallIn(public 'U'); %Service_EscalateLogin(public 'U'); %Service_GetInfo(no such resource, so no check); %Service_MCPGateway(public 'U'); %Service_Terminal(public 'U'); %Service_WebGateway(public 'U');
(a) services not open to the user 15
(a) web applications that are enabled, take a password and give the user USE (or have no resource): /api/admin [resource '' type 2]; /api/deepsee [resource '' type 2]; /api/docdb [resource '' type 2]; /api/fhir-explorer [resource '' type 2]; /api/healthshare-rest/hssys [resource '' type 2]; /api/iknow [resource '' type 2]; /api/interop-editors [resource '' type 2]; /api/mgmnt [resource '' type 2]; /api/security-config [resource '' type 2]; /csp/fhir-management/api [resource '' type 2]; /csp/fhirsql/api/repository [resource '' type 2]; /csp/fhirsql/api/ui [resource '' type 2]; /csp/healthshare [resource '' type 2]; /csp/healthshare/hssys [resource '' type 2]; /csp/healthshare/hssys/app/api [resource '' type 2]; /csp/healthshare/hssys/services [resource '' type 2]; /csp/healthshare/ocutalon [resource '' type 2]; /csp/healthshare/ocutalon/bulkfhir/api [resource '' type 2]; /csp/healthshare/ocutalon/services [resource '' type 2]; /csp/hscustom [resource '' type 2]; /csp/hssys [resource '' type 2]; /csp/sys [resource '' type 3]; /csp/sys/sec [resource '' type 3]; /csp/user [resource '' type 2]; /isc/studio/rules [resource '' type 3]; /isc/studio/usertemplates [resource '' type 2]; /ocutalon [resource '' type 2]; /ocutalon/api [resource '' type 2]; /ocutalon/trace/ocuorders [resource '' type 2]; /ocutalon/trace/ocutalon [resource '' type 2];
(a) web applications not open to the user 23
(e) connection record: [16] ~~~~~~zzSqlTask0~~zzSqlTask0~~~~~~~%~jdbc:IRIS://127.0.0.1:1972/OCUTALON"~com.intersystems.jdbc.IRISDriver<~/usr/irissys/dev/java/lib/1.8/intersystems-jdbc-3.11.0.jar~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ ; [17] ~~~~~~zzSqlTask0n~~zzSqlTask0n~~~~~~~%~jdbc:IRIS://127.0.0.1:1972/OCUTALON"~com.intersystems.jdbc.IRISDriver<~/usr/irissys/dev/java/lib/1.8/intersystems-jdbc-3.11.0.jar~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ ;
(f) %Service_CallIn public permission 'U', %Service_SQL 'U', %Service_Bindings absent, %Service_Native '', %Gateway_SQL '', %Gateway_Object '', %DB_OCUTALON_DATA '', %DB_OCUTALON_CODE ''
(a) native API connect ok
(a) native API global read refused: ERROR #5001: Exception returned: <PROTECT>
(a) native API class method refused: ERROR #5001: Exception returned: <PROTECT>
(a) native API session global read refused: ERROR #5001: Exception returned: <PROTECT>
(a) process of the reader: pid 6494 user zzSqlTask0 routine %SYS.DBSRV.1 jobtype 28 client %Net.DB.Connection ns OCUTALON
(a) native API write refused: ERROR #5001: Exception returned: <PROTECT>
(a) HTTP /api/mgmnt/ as the reader: status 403  body {"msg":"ERROR #8754: Unable to use namespace: USER."}
(a) HTTP /csp/sys/UtilHome.csp as the reader: status 200  body <html lang="en" >  <head>  <title>IRIS - Home</title>     <link rel="stylesheet" type="text/css" hre
(a) HTTP /csp/sys/exp/%25CSP.UI.Portal.SQL.Home.zen as the reader: status 200  body <html lang="en">  <head>   <title>Login IRIS</title>  <link rel="icon" type="image/ico" href="portal
(a) HTTP /api/atelier/ as the reader: status 401  body
(a) HTTP /api/docdb/v1/OCUTALON/ as the reader: status 403  body {"status":{"errors":[{"error":"ERROR #822: Access Denied","code":822,"domain":"%ObjectErrors","id":"
(a) HTTP /csp/healthshare/ocutalon/services/ as the reader: status 404  body
(a) control, no credentials /api/mgmnt/: status 401
connection zzSqlTask0d saved 1 , pwd property after save is empty
(c) data-only role, no SQL grant: FAILED <GATEWAY> java.sql.SQLException com.intersystems.jdbc.IRISConnection.connect(IRISConnection.java:781) [InterSystems IRIS JDBC] Communication link failure: Access Denied
(c) data-only role, SELECT granted on Gr: connected, ran, rows 1, ungranted: ERROR sqlcode -400 <GATEWAY> java.sql.SQLException  [SQLCODE: <-99>:<Privilege violation>]
(a) with %Service_SQL disabled: connected, select: ran, rows 1
(a) with %Service_Bindings disabled: FAILED <GATEWAY> java.sql.SQLException com.intersystems.jdbc.IRISConnection.connect(IRISConnection.java:781) [InterSystems IRIS JDBC] Communication link failure: Access Denied
(d) audit rows scanned 52098, containing the password 0
(d) event log rows scanned 76, containing the password 0
(d) messages are scanned through the database files below (no message of this run names a password)
(d) grep iris.cpf rc 1 files containing the password: none
(d) grep mgr rc 1 files containing the password: none
(d) grep mgr/journal rc 1 files containing the password: none
(d) grep /tmp rc 0 files containing the password: <pwfile>,
(d) grep /home rc 2 files containing the password: none
(d) %Prepare 'SELECT COUNT(*) FROM zzTask0.Gr' -> ok statementType '1'
(d) %Prepare 'SELECT 1' -> ok statementType '1'
(d) %Prepare '  select Id from zzTask0.Gr  ' -> ok statementType '1'
(d) %Prepare 'SELECT 1;' -> ok statementType '1'
(d) %Prepare 'SELECT 1; DELETE FROM zzTask0.Dm' -> error ERROR #5540: SQLCODE: -25 Message:  Input (;) encountered after end of query^ SELECT ? ; statementType ''
(d) %Prepare 'INSERT INTO zzTask0.Dm (Id, V) VALUES (9, 'x')' -> ok statementType '2'
(d) %Prepare 'UPDATE zzTask0.Dm SET V = 'x'' -> ok statementType '3'
(d) %Prepare 'DELETE FROM zzTask0.Dm' -> ok statementType '4'
(d) %Prepare 'CREATE TABLE zzTask0.Made (Id INTEGER)' -> ok statementType '9'
(d) %Prepare 'DROP TABLE zzTask0.Dr' -> ok statementType '11'
(d) %Prepare 'CALL %SYSTEM.SQL.Functions_Foo()' -> error ERROR #5540: SQLCODE: -428 Message:  Stored Procedure 'SQL.FUNCTIONS_FOO' not found statementType ''
(d) %Prepare '' -> error ERROR #5540: SQLCODE: -51 Message:  An SQL statement expected, LITERAL (1) found statementType ''
(d) %Prepare 'SELECT * FROM' -> error ERROR #5540: SQLCODE: -1 Message:  IDENTIFIER expected, <end of statement> found ^ SELECT  statementType ''
(d) %Prepare 'WITH x AS (SELECT 1 a) SELECT a FROM x' -> ok statementType '1'
(d) %Prepare 'SELECT 1 UNION SELECT 2' -> ok statementType '1'
(d) %Prepare 'EXPLAIN SELECT 1' -> ok statementType '1'
```
