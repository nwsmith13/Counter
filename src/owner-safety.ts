import type { Employee, EmployeeRole } from './identity'

export const preservesActiveOwner = (
  employees: Employee[],
  targetId: string,
  next: Pick<Employee, 'role' | 'active'>,
) => {
  const target = employees.find(employee => employee.id === targetId)
  if (!target) return true
  const nextEmployees = employees.map(employee => employee.id === targetId ? { ...employee, ...next } : employee)
  return nextEmployees.some(employee => employee.active && employee.role === 'OWNER')
}

export const ownerEdit = (role: EmployeeRole, active: boolean) => ({ role, active })

