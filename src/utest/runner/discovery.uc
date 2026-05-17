import * as fs from 'fs';

export function find_files(pattern) {
	let files = fs.glob(pattern) || [];
	sort(files);
	return files;
};
