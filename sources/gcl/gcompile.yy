%{
//
// FILE: gcompile.yy -- yaccer/compiler for the GCL
//
// This parser/compiler is dedicated to the memory of
// Jan L. A. van de Snepscheut, who wrote a program after which
// this code is modeled.
//
// $Id$
//

#include <stdlib.h>
#include <ctype.h>
#include "base/gmisc.h"
#include "base/gstream.h"
#include "base/gtext.h"
#include "math/rational.h"
#include "base/glist.h"
#include "base/gstack.h"
#include "gsm.h"
#include "gsminstr.h"
#include "gsmfunc.h"
#include "portion.h"

#include "base/system.h"

gStack<gText> GCL_InputFileNames(4);

static GSM *gsm; \
static bool record_funcbody, in_funcdecl;
static unsigned int current_char, current_line;
static gText current_expr, current_file, current_rawline;
static gText funcbody, funcname, funcdesc, paramtype, functype; 
static gList<gText> formals, types; 
static gList<Portion *> portions;
static gList<bool> refs;
static gStack<gText> funcnames;
static gText tval;
static gclExpression *exprtree;
static gTriState bval;
static double dval;
static gInteger ival;

static char nextchar(void);
static void ungetchar(char c);

static gclExpression *NewFunction(gclExpression *expr);
static gclExpression *DeleteFunction(void);
static void RecoverFromError(void);

int GCLParse(const gText& line, const gText &file,
             int lineno, const gText& rawline); 
int Execute(void); 

void gcl_yyerror(char *s);
int gcl_yylex(void);

%}

%union  {
  gclExpression *eval;
  gclParameterList *pval;
  gclReqParameterList *rpval; 
  gclOptParameterList *opval;
  gclListConstant *lcval;
}

%type <eval> expression constant function parameter
%type <pval> parameterlist
%type <rpval> reqparameterlist 
%type <opval> optparameterlist
%type <lcval> list listels

%token LOR
%token LAND
%token LNOT
%token EQU
%token NEQ
%token LTN
%token LEQ
%token GTN
%token GEQ
%token PLUS
%token MINUS
%token STAR
%token SLASH
%token ASSIGN
%token SEMI
%token LBRACK
%token DBLLBRACK
%token RBRACK
%token LBRACE
%token RBRACE
%token RARROW
%token LARROW
%token DBLARROW
%token COMMA
%token HASH
%token DOT
%token CARET
%token UNDERSCORE
%token AMPER
%token WRITE
%token READ
%token PERCENT
%token DIV
%token LPAREN
%token RPAREN
%token DOLLAR

%token IF
%token WHILE
%token FOR
%token NEWFUNC
%token DELFUNC
%token TYPEDEF
%token INCLUDE

%token NAME
%token BOOLEAN
%token INTEGER
%token FLOAT
%token TEXT
%token STDOUT
%token gNULL
%token FLOATPREC
%token RATIONALPREC

%token CRLF
%token EOC

%right  SEMI
%left  UWRITE
%right  ASSIGN
%left  WRITE  READ
%left  LOR
%left  LAND
%left  LNOT
%nonassoc  EQU  NEQ  LTN  LEQ  GTN  GEQ
%left  PLUS  MINUS  AMPER
%left  STAR  SLASH  PERCENT  DIV  DOT  
%left  CARET
%left  UMINUS
%left  HASH  UNDERSCORE


%%

program: expression  EOC  { exprtree = $1; return 0; }
       | error EOC    { RecoverFromError(); return 1; }
       | error CRLF   { RecoverFromError(); return 1; }
       ;
 
expression:      constant
          |      function
          |      LPAREN expression RPAREN   { $$ = $2; }
          |      expression SEMI expression
              { $$ = new gclSemiExpr($1, $3); }
          |      expression SEMI
	      { $$ = $1; }
          |      expression ASSIGN expression 
              { $$ = new gclAssignment($1, $3); }
	  |      expression ASSIGN
              { $$ = new gclUnAssignment($1); }
          |      WRITE expression   %prec UWRITE
              { $$ = new gclFunctionCall("Print", $2,
					 current_line, current_file); } 
          |      expression HASH expression
              { $$ = new gclFunctionCall("NthChild", $1, $3,
					 current_line, current_file); }
          |      expression UNDERSCORE expression
              { $$ = new gclFunctionCall("NthElement", $1, $3,
					 current_line, current_file); }
          |      expression PLUS expression
              { $$ = new gclFunctionCall("Plus", $1, $3,
					 current_line, current_file); }
          |      expression MINUS expression
              { $$ = new gclFunctionCall("Minus", $1, $3,
					 current_line, current_file); }
          |      expression AMPER expression  
              { $$ = new gclFunctionCall("Concat", $1, $3,
					 current_line, current_file); }
          |      PLUS expression    %prec UMINUS
              { $$ = $2; }
          |      MINUS expression   %prec UMINUS
              { $$ = new gclFunctionCall("Negate", $2,
					 current_line, current_file); }
          |      expression STAR expression
              { $$ = new gclFunctionCall("Times", $1, $3,
					 current_line, current_file); }
          |      expression SLASH expression
              { $$ = new gclFunctionCall("Divide", $1, $3,
					 current_line, current_file); }
          |      expression PERCENT expression
              { $$ = new gclFunctionCall("Modulus", $1, $3,
					 current_line, current_file); }
          |      expression DIV expression
              { $$ = new gclFunctionCall("IntegerDivide", $1, $3,
					 current_line, current_file); }
          |      expression DOT expression
              { $$ = new gclFunctionCall("Dot", $1, $3,
					 current_line, current_file); }
          |      expression CARET expression
              { $$ = new gclFunctionCall("Power", $1, $3,
					 current_line, current_file); }
          |      expression EQU expression
              { $$ = new gclFunctionCall("Equal", $1, $3,
					 current_line, current_file); }
          |      expression NEQ expression
              { $$ = new gclFunctionCall("NotEqual", $1, $3,
					 current_line, current_file); }
          |      expression LTN expression
              { $$ = new gclFunctionCall("Less", $1, $3,
					 current_line, current_file); }
          |      expression LEQ expression
              { $$ = new gclFunctionCall("LessEqual", $1, $3,
					 current_line, current_file); }
          |      expression GTN expression
              { $$ = new gclFunctionCall("Greater", $1, $3,
					 current_line, current_file); }
          |      expression GEQ expression
              { $$ = new gclFunctionCall("GreaterEqual", $1, $3,
					 current_line, current_file); }
          |      LNOT expression
              { $$ = new gclFunctionCall("Not", $2,
					 current_line, current_file); }
          |      expression LAND expression
              { $$ = new gclFunctionCall("And", $1, $3,
					 current_line, current_file); }
          |      expression LOR expression
              { $$ = new gclFunctionCall("Or", $1, $3,
					 current_line, current_file); }
	  |      expression WRITE expression
              { $$ = new gclFunctionCall("Write", $1, $3,
					 current_line, current_file); }
          |      expression READ expression
              { $$ = new gclFunctionCall("Read", $1, $3,
					 current_line, current_file); }
          ;

function:        IF LBRACK expression COMMA expression COMMA
                           expression RBRACK
              { $$ = new gclConditional($3, $5, $7); } 
        |        IF LBRACK expression COMMA expression RBRACK
              { $$ = new gclConditional($3, $5, 
				new gclConstExpr(new BoolPortion(false))); }
        |        WHILE LBRACK expression COMMA expression RBRACK
              { $$ = new gclWhileExpr($3, $5); }
	|        FOR LBRACK expression COMMA expression COMMA
                            expression COMMA expression RBRACK
              { $$ = new gclForExpr($3, $5, $7, $9); }
        |        NEWFUNC { if (in_funcdecl) YYERROR;  in_funcdecl = true; }
                  LBRACK signature COMMA 
                  { funcbody = ""; record_funcbody = true; }
                  expression RBRACK
                  { record_funcbody = false; in_funcdecl = false;
                    $$ = NewFunction($7); }
        |        DELFUNC { if (in_funcdecl) YYERROR; }
                  LBRACK signature RBRACK
                  { $$ = DeleteFunction(); }
        |        funcname LBRACK  { funcnames.Push(tval); } parameterlist RBRACK
              { $$ = new gclFunctionCall(funcnames.Pop(), $4,
					 current_line, current_file); }

funcname:          NAME
        |          FLOATPREC  { tval = "Float"; } 
        |          RATIONALPREC  { tval = "Rational"; }
        ;

parameterlist:     { $$ = new gclParameterList; }
             |     reqparameterlist  { $$ = new gclParameterList($1); }
             |     optparameterlist  { $$ = new gclParameterList($1); }
             |     reqparameterlist COMMA optparameterlist
                        { $$ = new gclParameterList($1, $3); }

reqparameterlist:  parameter  { $$ = new gclReqParameterList($1); }
             |     reqparameterlist COMMA parameter  { $1->Append($3); }

parameter:       expression

optparameterlist:  NAME  { funcnames.Push(tval); } arrow expression
                         { $$ = new gclOptParameterList(funcnames.Pop(), $4); }
                |  optparameterlist COMMA NAME  { funcnames.Push(tval); }
	              arrow expression
                         { $1->Append(funcnames.Pop(), $6); }

arrow:         RARROW | DBLARROW

constant:        BOOLEAN 
          { $$ = new gclConstExpr(new BoolPortion(bval)); }
        |        INTEGER   
          { $$ = new gclConstExpr(new NumberPortion(ival)); }
        |        FLOAT
          { $$ = new gclConstExpr(new NumberPortion(dval)); }
        |        TEXT
          { $$ = new gclConstExpr(new TextPortion(tval)); }
        |        STDOUT
          { $$ = new gclConstExpr(new OutputPortion(gsm->OutputStream())); }
        |        gNULL
          { $$ = new gclConstExpr(new OutputPortion(*new gNullOutput)); }
        |        FLOATPREC
          { $$ = new gclConstExpr(new PrecisionPortion(precDOUBLE)); }
        |        RATIONALPREC
          { $$ = new gclConstExpr(new PrecisionPortion(precRATIONAL)); }
        |        NAME
          { $$ = new gclVarName(tval); }
        |        DOLLAR NAME
          { $$ = new gclVarName(gText("$") + tval); }
        |        DOLLAR DOLLAR NAME
          { $$ = new gclVarName(gText("$$") + tval); }   
        |        list   { $$ = $1; }
        ;

list:            LBRACE RBRACE  { $$ = new gclListConstant; }
    |            LBRACE listels RBRACE  { $$ = $2; }
    ;

listels:         expression   { $$ = new gclListConstant($1); }
       |         listels COMMA expression { $1->Append($3); }
       ;


signature:       funcname  { funcname = tval; }   LBRACK
                   formallist RBRACK TYPEopt

TYPEopt:         { functype = "ANYTYPE"; }
       |         TYPEDEF  { paramtype = ""; } typename
                 { functype = paramtype; }

typename:        starname
        |        NAME  { paramtype += tval; } optparen

optparen:        
        |        LPAREN { paramtype += '('; } typename
                 RPAREN { paramtype += ')'; }

starname:        NAME  { paramtype += tval; } STAR { paramtype += '*'; }

formallist:      
          |      formalparams

formalparams:    formalparam
            |    formalparams COMMA formalparam

formalparam:     NAME  { formals.Append(tval); }  binding
                 { paramtype = ""; }  typename
                 { types.Append(paramtype); portions.Append(REQUIRED); }
           |     LBRACE NAME  { formals.Append(tval); }  binding
                 { paramtype = ""; types.Append(paramtype); }
                 expression RBRACE
                 { {
                   Portion *_p_ = $6->Evaluate(*gsm);
                   if (_p_->Spec().Type != porREFERENCE)
                     portions.Append(_p_);
                   else  {
                     delete _p_;
	             portions.Append(REQUIRED);
                   }
                   delete $6;
                 } }    

binding:         RARROW    { refs.Append(false); }
       |         DBLARROW  { refs.Append(true); }


%%


const char CR = (char) 10;

char nextchar(void)
{
  char c = current_expr[current_char];
  if( c == '\r' || c == '\n' )
    ++current_line;
  ++current_char;
  return c;
}

void ungetchar(char /*c*/)
{
  char c = current_expr[current_char-1];
  if( (current_char > 0) && (c == '\r' || c == '\n') )
    --current_line;
  --current_char;
}

typedef struct tokens  { long tok; char *name; } TOKENS_T;

void gcl_yyerror(char *s)
{
static struct tokens toktable[] =
{ { LOR, "OR or ||" },  { LAND, "AND or &&" }, { LNOT, "NOT or !" },
    { EQU, "=" }, { NEQ, "!=" }, { LTN, "<" }, { LEQ, "<=" },
    { GTN, ">" }, { GEQ, ">=" }, { PLUS, "+" }, { MINUS, "-" },
    { STAR, "*" }, { SLASH, "/" }, { ASSIGN, ":=" }, { SEMI, ";" },
    { LBRACK, "[" }, { DBLLBRACK, "[[" }, { RBRACK, "]" },
    { LBRACE, "{" }, { RBRACE, "}" }, { RARROW, "->" },
    { LARROW, "<-" }, { DBLARROW, "<->" }, { COMMA, "," }, { HASH, "#" },
    { DOT, "." }, { CARET, "^" }, { UNDERSCORE, "_" },
    { AMPER, "&" }, { WRITE, "<<" }, { READ, ">>" }, { DOLLAR, "$" },
    { IF, "If" }, { WHILE, "While" }, { FOR, "For" },
    { NEWFUNC, "NewFunction" }, { DELFUNC, "DeleteFunction" },
    { TYPEDEF, "=:" }, { INCLUDE, "Include" },
    { PERCENT, "%" }, { DIV, "DIV" }, { LPAREN, "(" }, { RPAREN, ")" },
    { CRLF, "carriage return" }, { EOC, "carriage return" },
    { FLOATPREC, "Float" }, { RATIONALPREC, "Rational" }, { 0, 0 }
};

  gsm->ErrorStream() << s << " at line " << current_line << " in file " << current_file
       << ": ";

  for (int i = 0; toktable[i].tok != 0; i++)
    if (toktable[i].tok == gcl_yychar)   {
      gsm->ErrorStream() << toktable[i].name << '\n';
      return;
    }

  switch (gcl_yychar)   {
    case NAME:
      gsm->ErrorStream() << "identifier " << tval << '\n';
      break;
    case BOOLEAN:
      if (bval == triTRUE)
     	gsm->ErrorStream() << "True\n";
      else if (bval == triFALSE)
        gsm->ErrorStream() << "False\n";
      else  /* (bval == triUNKNOWN) */
        gsm->ErrorStream() << "Unknown\n";
      break;
    case FLOAT:
      gsm->ErrorStream() << "floating-point constant " << dval << '\n';
      break;
    case INTEGER:
      gsm->ErrorStream() << "integer constant " << ival << '\n';
      break;
    case TEXT:
      gsm->ErrorStream() << "text string " << tval << '\n';
      break;
    case STDOUT:
      gsm->ErrorStream() << "StdOut\n";
      break;
    case gNULL:
      gsm->ErrorStream() << "NullOut\n";
      break;
    default:
      if (isprint(gcl_yychar) && !isspace(gcl_yychar))
        gsm->ErrorStream() << ((char) gcl_yychar) << '\n';
      else 
        gsm->ErrorStream() << "nonprinting character " << gcl_yychar << '\n';
      break;
  }    
}

int gcl_yylex(void)
{
  char c;
  
  do  {
    c = nextchar();
  }  while (isspace(c) || c == '\r' || c == '\n');

  if (isalpha(c))  {
    gText s(c);
    c = nextchar();
    while (isalpha(c) || isdigit(c))   {
      s += c;
      c = nextchar();
    }
    ungetchar(c);

    if (s == "True")   {
      bval = triTRUE;
      return BOOLEAN;
    }
    else if (s == "False")  {
      bval = triFALSE;
      return BOOLEAN;
    }
    else if (s == "Unknown") {
      bval = triUNKNOWN;
      return BOOLEAN;
    }
    else if (s == "StdOut") return STDOUT;
    else if (s == "NullOut")   return gNULL;
    else if (s == "AND")    return LAND;
    else if (s == "OR")     return LOR;
    else if (s == "NOT")    return LNOT;
    else if (s == "DIV")    return DIV;
    else if (s == "MOD")    return PERCENT;
    else if (s == "If")     return IF;
    else if (s == "While")  return WHILE;
    else if (s == "For")    return FOR;
    else if (s == "NewFunction")   return NEWFUNC;
    else if (s == "DeleteFunction")   return DELFUNC;
    else if (s == "Float")   return FLOATPREC;
    else if (s == "Rational")  return RATIONALPREC;
    else if (s == "Include")   return INCLUDE;
    else  { tval = s; return NAME; }
  }

  if (c == '"')   {
    tval = "";
    bool quote = true;
    bool check_digraph = true;
    while( quote )
    {
      c = nextchar();
      tval += c;
      
      if( check_digraph && 
          tval.Length() >= 2 && 
          tval[ tval.Length() - 2 ] == '\\' )
      {
        switch( c )
        {
	case '\'':
	case '\"':
	case '\?':
	case '\\':
          tval = tval.Left( tval.Length() - 2 ) + gText(c);
          check_digraph = false;
          break;
        case 'a':
          tval = tval.Left( tval.Length() - 2 ) + gText('\a');
          check_digraph = false;
          break;            
        case 'b':
          tval = tval.Left( tval.Length() - 2 ) + gText('\b');
          check_digraph = false;
          break;            
        case 'f':
          tval = tval.Left( tval.Length() - 2 ) + gText('\f');
          check_digraph = false;
          break;            
        case 'n':
          tval = tval.Left( tval.Length() - 2 ) + gText('\n');
          check_digraph = false;
          break;            
        case 'r':
          tval = tval.Left( tval.Length() - 2 ) + gText('\r');
          check_digraph = false;
          break;            
        case 't':
          tval = tval.Left( tval.Length() - 2 ) + gText('\t');
          check_digraph = false;
          break;            
        case 'v':
          tval = tval.Left( tval.Length() - 2 ) + gText('\v');
          check_digraph = false;
          break;            
        } // switch( c )
      }
      else
      {
        check_digraph = true;
        if( c == '\"' )
        {
          tval = tval.Left( tval.Length() - 1 );
          quote = false;
        }
      }
    } // while( quote )
    return TEXT;
  }

  if (isdigit(c))   {
    gText s(c);
    c = nextchar();
    while (isdigit(c))   {
      s += c;
      c = nextchar();
    }

    if (c == '.')   {
      s += c;
      c = nextchar();
      while (isdigit(c))  {
	s += c;
	c = nextchar();
      }

      ungetchar(c);
      dval = atof((char *) s);
      return FLOAT;
    }
    else  {
      ungetchar(c);
      ival = atoI((char *) s);
      return INTEGER;
    }
  }

  switch (c)  {
    case ',':   return COMMA;
    case '.':   c = nextchar();
      if (c < '0' || c > '9')  { ungetchar(c);  return DOT; }
      else  {
	gText s(".");
	s += c;
        c = nextchar();
        while (isdigit(c))  {
	  s += c;
	  c = nextchar();
        }

        ungetchar(c);
        dval = atof((char *) s);
        return FLOAT;
      }

    case ';':   return SEMI;
    case '_':   return UNDERSCORE;
    case '(':   return LPAREN;
    case ')':   return RPAREN;
    case '{':   return LBRACE;
    case '}':   return RBRACE;
    case '+':   return PLUS;
    case '-':   c = nextchar();
                if (c == '>')  return RARROW;
                else  { ungetchar(c);  return MINUS; }
    case '*':   return STAR;
    case '/':   return SLASH;
    case '%':   return PERCENT;
    case '=':   c = nextchar();
                if (c == ':')  return TYPEDEF;
                else   { ungetchar(c);  return EQU; }  
    case '#':   return HASH;
    case '^':   return CARET;
    case '[':   c = nextchar();
                if (c == '[')  return DBLLBRACK;
                else   {
		  ungetchar(c);
		  return LBRACK;
		}
    case ']':   return RBRACK;
    case ':':   c = nextchar();
                if (c == '=')  return ASSIGN;
                else   { ungetchar(c);  return ':'; }  
    case '!':   c = nextchar();
                if (c == '=')  return NEQ;
		else   { ungetchar(c);  return LNOT; }
    case '<':   c = nextchar();
                if (c == '=')  return LEQ;
	        else if (c == '<')  return WRITE; 
                else if (c != '-')  { ungetchar(c);  return LTN; }
                else   { 
		  c = nextchar();
		  if (c == '>')   return DBLARROW;
		  ungetchar(c);
		  return LARROW;
		}
    case '>':   c = nextchar();
                if (c == '=')  return GEQ;
                else if (c == '>')  return READ;
                else   { ungetchar(c);  return GTN; }
    case '&':   c = nextchar();
                if (c == '&')  return LAND;
                else   { ungetchar(c);  return AMPER; }
    case '|':   c = nextchar();
                if (c == '|')  return LOR;
                else   { ungetchar(c);  return '|'; }
    case '$':   return DOLLAR;
    case '\0':  return EOC;
    case CR:    assert(0);
    default:    return c;
  }
}

int GCLParse(GSM *p_gsm,
	     const gText& line, const gText &file, int lineno,
             const gText& rawline)
{
  gsm = p_gsm;
  current_expr = line;
  current_char = 0;
  current_file = file;
  current_line = lineno;
  current_rawline = rawline;

  for (unsigned int i = 0; i < line.Length(); i++)   {
    if (!isspace(line[i]))  {	
      if (!gcl_yyparse())  {	
        Execute();
        if (exprtree)   delete exprtree;
      }

      return 1;
    }
  }

  return 0;
}


void RecoverFromError(void)
{
  in_funcdecl = false;
  formals.Flush();
  types.Flush();
  refs.Flush();
  portions.Flush();
}
    

gclExpression *NewFunction(gclExpression *expr)
{
  gclFunction *func = new gclFunction(*gsm, funcname, 1);
  PortionSpec funcspec;

  try {
    funcspec = TextToPortionSpec(functype);
  }
  catch (gclRuntimeError &)  {
    gsm->ErrorStream() << "Error: Unknown type " << functype << ", " << 
      " as return type in declaration of " << funcname << "[]\n";
    return new gclConstExpr(new BoolPortion(false));;
  }

  gclSignature funcinfo = 
    gclSignature(expr, funcspec, formals.Length());

  funcbody = current_rawline;
  if( !strstr((const char *) funcbody, "/*Private*/" ) )
    funcinfo.Desc = funcbody;
  else
    funcinfo.Desc = "/*Private*/";

  if( funcdesc.Length() > 0 )
    funcinfo.Desc += "\n\n" + funcdesc;
  funcdesc = "";
  
  func->SetFuncInfo(0, funcinfo);

  for (int i = 1; i <= formals.Length(); i++)   {
    PortionSpec spec;
    if(portions[i])
      spec = portions[i]->Spec();
    else {
      try {
	spec = TextToPortionSpec(types[i]);
      }
      catch (gclRuntimeError &) {
	gsm->ErrorStream() << "Error: Unknown type " << types[i] << ", " << 
	  PortionSpecToText(spec) << " for parameter " << formals[i] <<
	  " in declaration of " << funcname << "[]\n";
	return new gclConstExpr(new BoolPortion(false));;
      }
    }

    if (refs[i])
      func->SetParamInfo(0, i - 1, 
			 gclParameter(formals[i], spec,
				       portions[i], BYREF));
      else
	func->SetParamInfo(0, i - 1, 
			   gclParameter(formals[i], spec,
					 portions[i], BYVAL));
  }


  formals.Flush();
  types.Flush();
  refs.Flush();
  portions.Flush();
  
  return new gclFunctionDef(func, expr);
}


gclExpression *DeleteFunction(void)
{
  gclFunction *func = new gclFunction(*gsm, funcname, 1);

  PortionSpec funcspec;

  try  {
    funcspec = TextToPortionSpec(functype);
  }
  catch (gclRuntimeError &)  {
    gsm->ErrorStream() << "Error: Unknown type " << functype << ", " << 
      PortionSpecToText(funcspec) << " as return type in declaration of " << 
      funcname << "[]\n";
    return new gclConstExpr(new BoolPortion(false));
  }

  func->SetFuncInfo(0, gclSignature((gclExpression *) 0, funcspec, formals.Length()));

  for (int i = 1; i <= formals.Length(); i++)   {
    PortionSpec spec;

    try {
      if (portions[i])
	spec = portions[i]->Spec();
      else
	spec = TextToPortionSpec(types[i]);
      
      if (refs[i])
	func->SetParamInfo(0, i - 1, 
			   gclParameter(formals[i], spec,
			                portions[i], BYREF));
      else
	func->SetParamInfo(0, i - 1, 
			   gclParameter(formals[i], spec,
					portions[i], BYVAL));
    }
    catch (gclRuntimeError &) {
      gsm->ErrorStream() << "Error: Unknown type " << types[i] << ", " << 
	PortionSpecToText(spec) << " for parameter " << formals[i] <<
	" in declaration of " << funcname << "[]\n";
      return new gclConstExpr(new BoolPortion(false));
    }
  }

  formals.Flush();
  types.Flush();
  refs.Flush();
  portions.Flush();

  return new gclDeleteFunction(func);
}

#include "base/gstatus.h"
#include "gsm.h"

int Execute(void)
{
  try  {
    Portion *result = gsm->Execute(exprtree);
    if (result)  delete result;
  }
  catch (gclQuitOccurred &) {
    throw;
  }
  catch (gclRuntimeError &E) {
    gsm->OutputStream() << "ERROR: " << E.Description() << '\n';
  }
  catch (gException &E) {
    gsm->OutputStream() << "EXCEPTION: " << E.Description() << '\n';
  }

  return rcSUCCESS;
}