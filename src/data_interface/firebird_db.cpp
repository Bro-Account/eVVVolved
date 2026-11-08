/*
	This file is part of VVV (Virtual Volumes View)

	Copyright (C) 2007, the VVV Development team

	Author: Fulvio Senore

    VVV is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    VVV is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with VVV; if not, write to the Free Software
    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
*/

#include "firebird_db.h"
#include "data_error.h"

#include <wx/file.h>
#include <wx/filename.h>

using namespace IBPP;

// Firebird 5 refuses to open a catalog created by VVV 1.5 or older (Firebird
// 2.x, ODS 11). Its attach error does not always reach IBPP as a SQLException
// (the attach can appear to succeed and the follow-up ODS probe then fails
// with a LogicException), so inspect the database header page first. This keeps
// the existing ecWrongODS handling and its "convert the catalog" message.
static bool IsUnsupportedOldCatalog( const wxString& fileName )
{
	if( fileName.empty() || !wxFileName::FileExists( fileName ) )
		return false;

	wxFile file;
	if( !file.Open( fileName, wxFile::read ) )
		return false;

	unsigned char header[20] = { 0 };
	const ssize_t bytesRead = file.Read( header, sizeof(header) );
	file.Close();
	if( bytesRead != (ssize_t) sizeof(header) || header[0] != 1 )
		return false;	// not a Firebird database header page

	const unsigned int odsVersion = header[18] | ( (unsigned int) header[19] << 8 );
	if( (odsVersion & 0x8000) == 0 )
		return false;	// unknown format: let Firebird report the error

	// ODS 11 is Firebird 2.x (VVV 1.5 and older); Firebird 3 uses ODS 12.
	return ( odsVersion & 0xFF ) <= 11;
}

CFirebirdDB::CFirebirdDB( wxString serverName, wxString databaseName, wxString userName, wxString password )
{
	this->serverName = serverName;
	this->databaseName = databaseName;
	this->userName = userName;
	this->password = password;

	db = DatabaseFactory( CUtils::wx2std(serverName), CUtils::wx2std(databaseName), CUtils::wx2std(userName), CUtils::wx2std(password) );
	tr = NULL;
}

CFirebirdDB::~CFirebirdDB(void)
{
}

void CFirebirdDB::Connect(void) {
	// A catalog created by VVV 1.5 or older cannot be opened by Firebird 5.
	// Check the ODS version first so the user gets the "convert the catalog"
	// message instead of an IBPP LogicException.
	if( serverName.empty() && IsUnsupportedOldCatalog( databaseName ) ) {
		throw CDataErrorException( wxT("This catalog uses an unsupported on-disk structure."), CDataErrorException::ecWrongODS );
	}

	try {
		db->Connect();
	}
	catch( IBPP::SQLException& e ) {
		CDataErrorException::ErrorCause ec;
		if( CDataErrorException::ConvertFirebirdError( e.EngineCode(), ec )  )
			throw CDataErrorException( e.ErrorMessage(), ec );
		else
			throw;
	}
}

bool CFirebirdDB::TestServerConnection( wxString serverName ) {
	bool retVal;

	// try to connect to a non existing database with random username and password, just to see if we can find the server
	IBPP::Database db = IBPP::DatabaseFactory( CUtils::wx2std(serverName), "aasnmnfurhdtr", "dnmcunfjf", "mdsifnfj" );

	retVal = true;
	try {
		db->Connect();
		db->Disconnect();
	}
	catch( IBPP::SQLException& e ) {
		if( e.EngineCode() == 335544721 )
			retVal = false;
	}
	return retVal;
}

void CFirebirdDB::Disconnect(void) {
	db->Disconnect();
}

void CFirebirdDB::TransactionStart( bool readOnly ) {
	tr = TransactionFactory( db, readOnly ? amRead : amWrite );
	tr->Start();
}

void CFirebirdDB::TransactionCommit(void) {
	tr->Commit();
	tr = NULL;
}

void CFirebirdDB::TransactionCommitRetain(void) {
	tr->CommitRetain();
}

void CFirebirdDB::TransactionRollback(void) {
	tr->Rollback();
	tr = NULL;
}

bool CFirebirdDB::TransactionIsOpened(void) {
	return (tr != NULL);
}

void CFirebirdDB::CreateDatabaseOnDisk( wxString serverName, wxString userName, wxString password, wxString backupName, wxString databaseName ) {

	Service svc = ServiceFactory( CUtils::wx2std(serverName), CUtils::wx2std(userName), CUtils::wx2std(password) );
	svc->Connect();
	svc->StartRestore( CUtils::wx2std(backupName), CUtils::wx2std(databaseName), 8192 );
	svc->Wait();
	svc->Disconnect();
}

void CFirebirdDB::BackupDatabase( wxString serverName, wxString userName, wxString password, wxString backupName, wxString databaseName ) {
	Service svc = ServiceFactory( CUtils::wx2std(serverName), CUtils::wx2std(userName), CUtils::wx2std(password) );
	svc->Connect();
	svc->StartBackup( CUtils::wx2std(databaseName), CUtils::wx2std(backupName) );
	svc->Wait();
	svc->Disconnect();
}


int CFirebirdDB::GetDatabaseVersion(void) {
	int64_t tmp;
	int currentVersion;

	TransactionStart();
	Statement st = StatementFactory( GetIBPPDB(), TransactionGetReference() );
	try {
		st->Prepare( "SELECT DB_VERSION FROM SERVICE WHERE SERVICE_ID = 1" );
		st->Execute();
		st->Fetch();
		st->Get( "DB_VERSION", tmp );
		currentVersion = tmp;
	}
	catch( IBPP::SQLException& e ) {
		if( e.EngineCode() == 335544569 ) {
			// table not found: this is a very old database that does not contain the SERVICE table
			// we must create that table
			st->ExecuteImmediate( "CREATE TABLE SERVICE (SERVICE_ID BIGINT NOT NULL, DB_VERSION INTEGER NOT NULL)" );
			st->ExecuteImmediate( "ALTER TABLE SERVICE ADD CONSTRAINT PK_SERVICE PRIMARY KEY (SERVICE_ID)" );
			st->ExecuteImmediate( "UPDATE RDB$RELATIONS SET RDB$DESCRIPTION = 'This table contains service data' WHERE (RDB$RELATION_NAME = 'SERVICE')" );
			tr->CommitRetain();
			st->ExecuteImmediate( "INSERT INTO SERVICE (SERVICE_ID, DB_VERSION) VALUES (1, 0)" );
			currentVersion = 0;
		}
		else
			throw;
	}
	TransactionCommit();

	return currentVersion;
}


void CFirebirdDB::UpgradeDatabase( int currentVersion, int finalDBVersion ) {

	// open the database containing the metadata changes and reads them
	Database upgDb = DatabaseFactory( CUtils::wx2std(serverName), CUtils::wx2std(CUtils::GetStructUpdateDbName()), CUtils::wx2std(userName), CUtils::wx2std(password) );
	upgDb->Connect();
	Transaction upgTr = TransactionFactory( upgDb );
	upgTr->Start();
	wxString sql = wxT("SELECT VERSION_NUMBER, SCRIPT_CODE FROM UPDATE_SCRIPTS WHERE VERSION_NUMBER > ") + CUtils::long2string(currentVersion) + wxT(" AND VERSION_NUMBER <= ") + CUtils::long2string(finalDBVersion) + wxT(" ORDER BY VERSION_NUMBER");
	Statement stUpg = StatementFactory( upgDb, upgTr );
	stUpg->Execute( CUtils::DBwx2std(sql) );
	wxArrayString scripts;
	wxArrayString versions;
	int finalVersion = 0;
	while( stUpg->Fetch() ) {
		string s;
		stUpg->Get( "VERSION_NUMBER", finalVersion );
		stUpg->Get( "SCRIPT_CODE", s );
		scripts.Add( CUtils::DBstd2wx(s) );
		versions.Add( CUtils::long2string(finalVersion) );
	}
	upgTr->Commit();
	upgDb->Disconnect();

	wxASSERT( finalVersion > currentVersion );

	// now "scripts" contains all the scripts that must be executed to upgrade the current database

	// execute all the scripts
	TransactionStart();
	Statement st = StatementFactory( GetIBPPDB(), TransactionGetReference() );
	for( int k = 0; k < (int) scripts.GetCount(); k ++ ) {
		st->ExecuteImmediate( CUtils::DBwx2std(scripts[k]) );
		sql = wxT("UPDATE SERVICE SET DB_VERSION = ") + versions[k] + wxT(" WHERE SERVICE_ID = 1");
		st->ExecuteImmediate( CUtils::DBwx2std(sql) );
		TransactionCommitRetain();
	}
	sql = wxT("UPDATE SERVICE SET DB_VERSION = ") + CUtils::long2string(finalVersion) + wxT(" WHERE SERVICE_ID = 1");
	st->ExecuteImmediate( CUtils::DBwx2std(sql) );
	TransactionCommit();

}

void CFirebirdDB::UpdateStatistics( UpdateStatisticsTables ust ) {

	bool inTransaction = TransactionIsOpened();
	if( !inTransaction ) {
		TransactionStart();
	}
	Statement st = StatementFactory( GetIBPPDB(), TransactionGetReference() );
	st->Prepare( "EXECUTE PROCEDURE SP_SET_STATISTICS_TABLE( ? )" );

	if( ust == usAll || ust == usPhysical ) {
		st->Set( 1, "VOLUMES" );
		st->Execute();
		st->Set( 1, "PATHS" );
		st->Execute();
		st->Set( 1, "FILES" );
		st->Execute();
		st->Set( 1, "FILES_AUDIO_METADATA" );
		st->Execute();
	}
	if( ust == usAll || ust == usVirtual ) {
		st->Set( 1, "VIRTUAL_PATHS" );
		st->Execute();
		st->Set( 1, "VIRTUAL_FILES" );
		st->Execute();
	}

	if( !inTransaction ) {
		TransactionCommit();
	}
}


