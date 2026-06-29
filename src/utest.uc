/**
 * A modern, non-invasive testing framework for the ucode ecosystem.
 * This module is the primary entry point, providing the DSL, assertions, combinators, mock engine, and property-based testing utilities.
 *
 * @module utest
 */

import * as dsl from 'utest.dsl';
import * as _mock from 'utest.mock';
import * as _spy from 'utest.mock.spy';
import * as _assert from 'utest.assert';
import * as _combinators from 'utest.combinators';
import * as _property from 'utest.property';
import * as _generators from 'utest.generators';

export const describe = dsl.describe;
export const xdescribe = dsl.xdescribe;
export const it = dsl.it;
export const skip = dsl.skip;
export const xit = dsl.xit;
export const beforeEach = dsl.beforeEach;
export const afterEach = dsl.afterEach;
export const setup = dsl.setup;
export const teardown = dsl.teardown;

export const mock = _mock;
export const spy = _spy.spy;

export const assert = _assert;

export const equals = _combinators.equals;
export const contains = _combinators.contains;
export const truthy = _combinators.truthy;
export const falsy = _combinators.falsy;
export const not = _combinators.not;
export const pred = _combinators.pred;
export const any_order = _combinators.any_order;
export const any = _combinators.any;
export const regex = _combinators.regex;
export const starts_with = _combinators.starts_with;
export const ends_with = _combinators.ends_with;
export const has_length = _combinators.has_length;
export const between = _combinators.between;
export const is_type = _combinators.is_type;

export const prop = _property.prop;
export const forall = _property.forall;
export const gen = _generators;
export const is_generator = _generators.is_generator;
