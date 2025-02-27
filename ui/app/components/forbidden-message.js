/**
 * Copyright (c) HashiCorp, Inc.
 * SPDX-License-Identifier: BUSL-1.1
 */

import Component from '@ember/component';
import { tagName } from '@ember-decorators/component';
import { inject as service } from '@ember/service';

@tagName('')
export default class ForbiddenMessage extends Component {
  @service token;
  @service store;
  @service router;

  get authMethods() {
    return this.store.findAll('auth-method');
  }
}
