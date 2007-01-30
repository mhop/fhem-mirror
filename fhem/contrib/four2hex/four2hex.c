/*
Four2hex was written to convert the housecode based on digits ranging from 1
to 4 into hex code and vica versa. 
Four2hex is freeware based on the GNU Public license.

To built it:
$ make four2hex

Install it to /usr/local/bin:
$ su
# make install


Here an example from "four"-based to hex:
$ four2hex 12341234
1b1b

Here an example in the other (reverse) direction:
$ four2hex -r 1b1b
12341234

Enjoy.
Peter Stark, (Peter dot stark at t-online dot de)

*/

#include <stdio.h>
#include <ctype.h>

int atoh (const char c)
{
	int ret=0;

	ret = (int) (c - '0');
	if (ret > 9) {
		ret = (int) (c - 'a' + 10);
	}
	return ret;
}

int strlen(const char *);

main (int argc, char **argv)
{
	char c, *s, *four;
	long int result;
	int b, i, h;

	if (argc < 2 || argc >3) {
		fprintf (stderr, "usage: four2hex four-string\n");
		fprintf (stderr, "   or: four2hex -r hex-string\n");
		return (1);
	}
	result = 0L;
	if (strcmp(argv[1], "-r") == 0) {
		/* reverse (hex->4) */
		for (s = argv[2]; *s != '\0'; s++) {
			c = tolower(*s);
			b = atoh(c);
			for (i = 0; i < 2; i++) {
				h = ((b & 0xc) >> 2) + 1;
				b = (b & 0x3) << 2;
				printf ("%d", h);
			}
		}
		printf ("\n");
	} else {
		/* normal (4->hex) */
		four = argv[1];
		if (strlen(four) == 4 || strlen(four) == 8) {
			for (s = four; *s != '\0'; s++) {
				result = result << 2;
				switch (*s) {
					case '1' : result = result + 0; break;
					case '2' : result = result + 1; break;
					case '3' : result = result + 2; break;
					case '4' : result = result + 3; break;
					default :
						fprintf (stderr, "four-string may contain '1' to '4' only\n");
						break;
				}
			}
			if (strlen(four) == 8) {
			 	printf ("%04x\n", result);
			} else {
			 	printf ("%02x\n", result);
			}
		} else {
			fprintf (stderr, "four-string must be of length 4 or 8\n");
			return (1);
		}
	}
	return (0);
}
