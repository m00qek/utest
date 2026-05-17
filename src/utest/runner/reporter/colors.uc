const C_RESET = "\x1b[0m", 
      C_RED = "\x1b[31m", 
      C_BRED = "\x1b[91m", 
      C_GREEN = "\x1b[32m", 
      C_BOLD = "\x1b[1m", 
      C_YELLOW = "\x1b[33m",
      C_BLUE = "\x1b[34m",
      C_CYAN = "\x1b[36m";

export const color = (c, t) => (c ? sprintf("%s%s%s", c, t, C_RESET) : t);

export const THEME = {
	PASS: C_GREEN,
	FAIL: C_RED,
	ERROR: C_BRED,
	SKIP: C_YELLOW,
	IGNORE: C_BLUE,
	HEADER: C_CYAN,
	TIME: C_BOLD,
	BOLD: C_BOLD
};
