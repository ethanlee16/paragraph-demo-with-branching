import { v5 as uuidV5 } from 'uuid';

import projectConfig from '../.para/project.json';

export function generateWorkflowId(workflowId: string): string {
  return uuidV5(workflowId, projectConfig.projectId);
}

export function generateResourceId(resourceId: string): string {
  return uuidV5(resourceId, projectConfig.projectId);
}

export function generateTriggerId(triggerId: string): string {
  return uuidV5(triggerId, projectConfig.projectId);
}