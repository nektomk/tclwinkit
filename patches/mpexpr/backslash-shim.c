
/* ---- winkit patch: Tcl 9 removed the public Tcl_Backslash(). ----------
 * Compact equivalent of the Tcl 8.6 implementation for mpexpr's parser
 * (escape sequences \a\b\f\n\r\t\v, \<newline> continuation, \ooo octal,
 * \xHH.. hex, \uHHHH unicode, trailing backslash). */
#if TCL_MAJOR_VERSION > 8
static Tcl_UniChar
MpBackslash(char *src, int *readPtr)
{
    Tcl_UniChar result;
    int count;			/* chars consumed after the backslash */
    int i;
    char c;

    src++;			/* skip the backslash itself */
    c = *src++;
    switch (c) {
    case 'a': result = 0x07; count = 1; break;
    case 'b': result = 0x08; count = 1; break;
    case 'f': result = 0x0c; count = 1; break;
    case 'n': result = 0x0a; count = 1; break;
    case 'r': result = 0x0d; count = 1; break;
    case 't': result = 0x09; count = 1; break;
    case 'v': result = 0x0b; count = 1; break;
    case '\n':
	/* line continuation: yields a space, skips following spaces/tabs */
	result = ' ';
	count = 1;
	while (*src == ' ' || *src == '\t') { src++; count++; }
	break;
    case '\r':
	if (*src == '\n') { src++; count = 2; } else { count = 1; }
	while (*src == ' ' || *src == '\t') { src++; count++; }
	result = ' ';
	break;
    case '0': case '1': case '2': case '3':
    case '4': case '5': case '6': case '7':
	src--;			/* put the first digit back */
	result = 0;
	for (count = 0; count < 3; count++) {
	    c = *src;
	    if (c < '0' || c > '7') break;
	    result = result * 8 + (Tcl_UniChar)(c - '0');
	    src++;
	}
	if (count == 0) { count = 1; result = (Tcl_UniChar)(unsigned char)c; }
	break;
    case 'x':
	result = 0;
	for (count = 0; ; count++) {
	    c = *src;
	    if (c >= '0' && c <= '9')	  { i = c - '0'; }
	    else if (c >= 'a' && c <= 'f') { i = c - 'a' + 10; }
	    else if (c >= 'A' && c <= 'F') { i = c - 'A' + 10; }
	    else break;
	    result = result * 16 + (Tcl_UniChar)i;
	    src++;
	}
	if (count == 0) { count = 1; result = 'x'; }
	break;
    case 'u':
	result = 0;
	for (count = 0; count < 4; count++) {
	    c = *src;
	    if (c >= '0' && c <= '9')	  { i = c - '0'; }
	    else if (c >= 'a' && c <= 'f') { i = c - 'a' + 10; }
	    else if (c >= 'A' && c <= 'F') { i = c - 'A' + 10; }
	    else break;
	    result = result * 16 + (Tcl_UniChar)i;
	    src++;
	}
	if (count == 0) { count = 1; result = 'u'; }
	break;
    case '\0':
	/* trailing backslash at end of string */
	result = '\\';
	count = 0;
	break;
    default:
	result = (Tcl_UniChar)(unsigned char)c;
	count = 1;
	break;
    }
    if (readPtr != NULL) {
	*readPtr = count + 1;	/* +1 accounts for the backslash itself */
    }
    return result;
}
#define Tcl_Backslash MpBackslash
#endif /* TCL_MAJOR_VERSION > 8 */
/* ---- end winkit patch ---- */
